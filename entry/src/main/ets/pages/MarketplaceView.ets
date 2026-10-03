import { MARKET_CATEGORIES, MarketItem, MarketPage, MarketplaceClient } from '../adapters/MarketplaceClient';

/** Marketplace: search, categories, Install (-> the app's own import + "From the marketplace" consent). */
@ComponentV2
export struct MarketplaceView {
  /** Shown as a home tab (UI-2) instead of a pushed page. */
  @Param embedded: boolean = false;
  @Require @Param client: MarketplaceClient;
  @Event onInstall: (item: MarketItem) => void = () => {
  };
  @Local q: string = '';
  @Local tag: string = '';
  @Local items: MarketItem[] = [];
  @Local offline: boolean = false;
  @Local loading: boolean = false;
  @Local cursor: string = '';
  private seq: number = 0;

  aboutToAppear(): void {
    this.load(false);
  }

  private async load(more: boolean): Promise<void> {
    const mine = ++this.seq;
    this.loading = true;
    const page: MarketPage = await this.client.search(this.q, this.tag, more ? this.cursor : '');
    if (mine !== this.seq) {
      return; // a newer search replaced this one
    }
    this.items = more ? this.items.concat(page.items) : page.items;
    this.cursor = page.nextCursor;
    this.offline = page.offline;
    this.loading = false;
  }

  @Builder
  chip(label: string, value: string) {
    Text(label)
      .fontSize($r('sys.float.Body_M'))
      .fontColor(this.tag === value ? $r('sys.color.font_on_primary') : $r('sys.color.font_primary'))
      .height(34)
      .padding({ left: 14, right: 14 })
      .borderRadius(17)
      .backgroundColor(this.tag === value ? $r('sys.color.brand') : $r('sys.color.comp_background_tertiary'))
      .onClick(() => {
        this.tag = this.tag === value ? '' : value;
        this.load(false);
      })
  }

  @Builder
  card(item: MarketItem) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(item.name)
          .fontSize($r('sys.float.Subtitle_M'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Button('Install', { controlSize: ControlSize.SMALL })
          .onClick(() => this.onInstall(item))
      }
      .width('100%')
      if (item.description.length > 0) {
        Text(item.description)
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      Text([item.widget ? 'Widget' : '', item.installs > 0 ? `${item.installs} installs` : '']
        .concat(item.tags.slice(0, 3)).filter((s: string) => s.length > 0).join(' · '))
        .fontSize($r('sys.float.Caption_M'))
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  content() {
    Column({ space: 12 }) {
      Search({ value: this.q, placeholder: 'Search capsules' })
        .onChange((v: string) => {
          this.q = v;
        })
        .onSubmit(() => this.load(false))
      Scroll() {
        Row({ space: 8 }) {
          ForEach(MARKET_CATEGORIES, (c: string) => {
            this.chip(c.charAt(0).toUpperCase() + c.substring(1), c)
          }, (c: string) => c)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      if (this.offline) {
        Text(this.client.configured ? "The marketplace is offline right now. These examples come with the app." :
          'These examples come with the app.')
          .fontSize($r('sys.float.Caption_M'))
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
      }
      if (this.loading && this.items.length === 0) {
        LoadingProgress().width(40).height(40)
      } else if (this.items.length === 0) {
        Text('Nothing found. Try another word.')
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_tertiary'))
          .width('100%')
          .padding(16)
      } else {
        List({ space: 10 }) {
          ForEach(this.items, (item: MarketItem) => {
            ListItem() {
              this.card(item)
            }
          }, (item: MarketItem) => item.id)
          if (this.cursor.length > 0) {
            ListItem() {
              Button('More', { buttonStyle: ButtonStyleMode.TEXTUAL })
                .onClick(() => this.load(true))
            }
          }
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .contentEndOffset(this.embedded ? 120 : 0) // as a tab: scrolls under the floating bar, last card stays visible
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8 })
  }

  build() {
    if (this.embedded) {
      // A tab of the home screen (UI-2): no title bar, a large title, room for the floating tab bar.
      Column({ space: 8 }) {
        Text('Marketplace')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 12 })
        Column() {
          this.content()
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
    } else {
      NavDestination() {
        this.content()
      }
      .title('Marketplace')
      .backgroundColor($r('sys.color.background_secondary'))
    }
  }
}
