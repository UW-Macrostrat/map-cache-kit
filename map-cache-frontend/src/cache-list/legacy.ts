import { Component } from "@angular/core";
import { AlertController, ModalController } from "@ionic/angular";
import { CacheSystemStatus, MapCacheService } from "../map-cache.service";
import { CacheCreateModal, CacheFormData } from "../cache-create";
import { MapCachePriority } from "../models";
import { RockdComponent } from "~/components";
import { CacheManagementAction } from "./cache-listing";
export * from "./cache-listing";

@Component({
  selector: "page-map-caches",
  templateUrl: "map-caches.html",
})
export class MapCachesPage extends RockdComponent {
  cacheStatus: CacheSystemStatus = {
    ready: false,
    error: "Map cache system is not yet loaded.",
  };

  public deletingCache: boolean = false;
  public globalExists: boolean = false;
  public cacheReady: boolean = false;

  cacheMode: MapCachePriority = MapCachePriority.CacheThenNetwork;

  constructor(
    private cacheService: MapCacheService,
    public alertCtrl: AlertController,
    private modalController: ModalController,
  ) {
    super();

    this.dispatch = this.dispatch.bind(this);
  }

  ngOnInit() {
    this.subscribeTo(this.cacheService.status$, (d) => {
      this.cacheStatus = d;
    });
    this.subscribeTo(this.cacheService.mode$, (d) => {
      if (d == this.cacheMode) return;
      this.cacheMode = d;
    });
  }

  setCacheMode(cacheMode) {
    this.cacheService.setCacheMode(cacheMode);
  }

  ionViewDidLoad() {}

  dismiss() {
    this.modalController.dismiss();
  }

  async deleteCache(id: number) {
    await this.cacheService.deleteCache(id);
  }

  async createNewCache() {
    const modal = await this.modalController.create({
      component: CacheCreateModal,
    });

    modal.onDidDismiss<CacheFormData>().then((response) => {
      if (response.data == null) return;
      this.cacheService.createCacheWithFormResponse(response.data);
    });
    await modal.present();
  }

  dispatch(action: CacheManagementAction) {
    switch (action.type) {
      case "delete":
        return this.deleteCache(action.cacheId);
      case "refresh":
        return this.cacheService.startDownload(action.cacheId);
      case "view":
        return this.cacheService.viewCache(action.cacheId);
      case "cancel-download":
        return this.cacheService.stopDownload(action.cacheId);
      case "create-global":
        return this.cacheService.createGlobalCache();
      case "create":
        return this.createNewCache();
      case "delete-all":
        return this.deleteAll();
      case "delete-ambient":
        return this.cacheService.deleteAmbientCache();
      case "set-cache-mode":
        return this.setCacheMode(action.cacheMode);
    }
  }

  async deleteAll() {
    let alert = await this.alertCtrl.create({
      header: "Delete all caches",
      subHeader:
        "This will delete all map caches on your device and cannot be undone.",
      buttons: [
        {
          text: "Cancel",
          handler: () => {},
        },
        {
          text: "Delete",
          handler: this.cacheService.deleteAllCaches.bind(this.cacheService),
        },
      ],
    });
    await alert.present();
  }
}
