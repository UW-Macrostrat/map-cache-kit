import { useCallback } from "react";
import useWebSocket, { ReadyState } from "react-use-websocket";

export function useReconnectableWebSocket(baseURL: string, options = {}) {
  /** An expanded function to use a websocket */

  let uri = baseURL;
  // Get absolute and websocket URL
  if (!uri.startsWith("http")) {
    const { protocol, host } = window.location;
    uri = `${protocol}//${host}${uri}`;
  }
  uri = uri.replace(/^http(s)?:\/\//, "ws$1://");
  console.log(uri);

  const getSocketUrl: () => Promise<string> = useCallback(() => {
    return new Promise((resolve) => {
      let uri = baseURL;
      // Get absolute and websocket URL
      if (!uri.startsWith("http")) {
        const { protocol, host } = window.location;
        uri = `${protocol}//${host}${uri}`;
      }
      uri = uri.replace(/^http(s)?:\/\//, "ws$1://");
      resolve(uri);
    });
  }, [baseURL]);

  const socket = useWebSocket(uri, {
    shouldReconnect() {
      return true;
    },
    ...options,
  });

  const isOpen = socket.readyState == ReadyState.OPEN;

  return {
    ...socket,
    isOpen,
  };
}
