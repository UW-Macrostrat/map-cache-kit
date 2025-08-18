//
//  DownloadQueue.swift
//  MobileMapCache
//
//  Created by Daven Quinn on 8/17/25.
//
// https://losingfight.com/blog/2024/04/14/swift-asyncawait-do-you-even-need-a-queue/
import Vapor

func downloadFile(with app: Application, url: URI) async throws -> ClientResponse {
  return try await app.downloadManger.run {
    // wait for a randomized timeout
    let timeout = try app.config.httpRequestTimeout
    // scale timeout by a random amount
    //timeout *= Double.random(in: 0.5...1.5)
    var t1 = Double(timeout.nanoseconds) / 1_000_000_000.0
    t1 *= Double.random(in: 0.5...1.5)
    
    try await Task.sleep(nanoseconds: UInt64(t1 * 1_000_000_000.0))
  
    let client = app.client
    app.logger.debug("Downloading \(url)")
    // sleep for the timeout
    try Task.checkCancellation()
    
    do {
      let res = try await client.get(url)
      return res
    } catch let error {
      app.logger.error("Failed to download \(url): \(error)")
      throw error
    }
  }
}

final class ConcurrentDownloadManager: Sendable {
  private let counter: Counter
  
  actor Counter {
    /// The maximum amount of currency allowed
    private let concurrency: Int
    /// How many blocks are currently in flight
    private var inflightCount = 0
    /// Pending (blocked) blocks in a FIFO queue.
    private var pending = [Signal]()
    
    init(concurrency: Int) {
      self.concurrency = concurrency
    }
    
    func enterLimiting() -> Condition {
      let shouldWait = inflightCount >= concurrency
      
      let (condition, signal) = Condition.makeCondition()
      if shouldWait {
        pending.append(signal)
      } else {
        // immediately signal and let it run
        inflightCount += 1
        signal.signal()
      }
      
      return condition
    }
    
    func exitLimiting() {
      inflightCount -= 1
      let shouldUnblock = inflightCount < concurrency
      
      guard shouldUnblock, let firstPending = pending.first else {
        return
      }
      pending.removeFirst()
      inflightCount += 1
      firstPending.signal()
    }
    
    deinit {
      let localPending = pending
      pending.removeAll()
      for local in localPending {
        local.signal()
      }
    }
  }
  
  init(maxConcurrentDownloads: Int) {
    self.counter = Counter(concurrency: maxConcurrentDownloads)
  }
  
  func run<Value>(_ block: @escaping () async throws -> Value) async throws -> Value {
    let condition = await counter.enterLimiting()
    await condition.wait()
    
    do {
      let value = try await block()
      await counter.exitLimiting()
      return value
    } catch {
      await counter.exitLimiting()
      throw error
    }
  }
}


/// Signal is used in conjunction with Condition. Together they allow
/// one Task to wait on anther Task.
public final class Signal: Sendable {
  private let stream: AsyncStream<Void>.Continuation
  
  /// Private init, don't call directly. Instead, use Condition.makeCondition()
  fileprivate init(stream: AsyncStream<Void>.Continuation) {
    self.stream = stream
  }
  
  /// Signal the waiter (who has the Condition) that they're good to go
  public func signal() {
    stream.finish()
  }
}

/// Condition allows two async Tasks to coordinate. Use `makeCondition()` to
/// create a Condition/Signal pair. The Task that wants to wait on something to
/// happen takes the Condition, the Task that notifies of the condition takes
/// the Signal.
public struct Condition: Sendable {
  private let waiter: @Sendable () async -> Void
  
  /// Private init; create a closure that will can be waited on
  fileprivate init(waiter: @Sendable @escaping () async -> Void) {
    self.waiter = waiter
  }
  
  /// Wait on the condition to become true
  public func wait() async {
    await waiter()
  }
  
  /// Construct a Condition/Signal pair. The Task that wants to wait on something to
  /// happen takes the Condition, the Task that notifies of the condition takes
  /// the Signal.
  public static func makeCondition() -> (Condition, Signal) {
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    let condition = Condition {
      for await _ in stream {}
    }
    let signal = Signal(stream: continuation)
    return (condition, signal)
  }
}

