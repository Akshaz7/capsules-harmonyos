import { MARKET_CATEGORIES, MarketItem, MarketPage, MarketplaceClient } from '../adapters/MarketplaceClient';
import { Capsule } from '../core';
import { Chip, IconTile, OriginChip, PrimaryButton } from '../components';
import { Flags } from '../theme/Flags';
import { Palette, Radius } from '../theme/Tokens';
import { capsuleIcon } from './CapsuleEntry';

/** The capsule's own icon when its JSON is at hand; a bag otherwise. */
function itemIcon(item: MarketItem): Resource {
  if (item.capsuleJson !== undefined) {
    try {
      return capsuleIcon(JSON.parse(item.capsuleJson) as Capsule);
    } catch (e) {
      // fall through
    }
  }
  return $r('sys.symbol.bag');
}

/** Marketplace: search, categories, Install (-> the app's own import + "From the marketplace" consent). */
@ComponentV2
export struct MarketplaceView {
  /** Shown as a home tab (UI-2) instead of a pushed page. */
  @Param embedded: boolean = false;
  @Require @Param client: MarketplaceClient;
  /** T3-25: "On-device only" is on, so nothing is sent: the shipped examples and a note. */
  @Param onDeviceOnly: boolean = false;
  @Event onOpenSettings: () => void = () => {
  };
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

  /** The tab stays alive, so switching AI mode reloads (examples only, or the live list again). */
  @Monitor('onDeviceOnly')
  onModeChange(): void {
    this.cursor = '';
    this.load(false);
  }

  @Builder
  onDeviceNote() {
    Column({ space: 8 }) {
      Text("On-device only is on, so the marketplace isn't searched. Switch AI mode to Smart in Settings to browse it.")
        .fontSize(Flags.NEW_MARKET ? 14 : $r('sys.float.Body_M'))
        .fontColor(Flags.NEW_MARKET ? Palette.text : $r('sys.color.font_primary'))
        .width('100%')
      Button('Open Settings', { buttonStyle: ButtonStyleMode.NORMAL })
        .height(40)
        .fontColor(Flags.NEW_MARKET ? Palette.blue : undefined)
        .backgroundColor(Flags.NEW_MARKET ? Palette.surface : undefined)
        .onClick(() => this.onOpenSettings())
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .borderRadius(Flags.NEW_MARKET ? 18 : 16)
    .backgroundColor(Flags.NEW_MARKET ? Palette.tint : $r('sys.color.comp_background_primary'))
  }

  private async load(more: boolean): Promise<void> {
    const mine = ++this.seq;
    this.loading = true;
    const page: MarketPage = this.onDeviceOnly ? this.client.examples(this.q, this.tag) :
      await this.client.search(this.q, this.tag, more ? this.cursor : '');
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
      if (this.onDeviceOnly) {
        this.onDeviceNote()
      } else if (this.offline) {
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

  /** Redesign (NEW_MARKET): white preview tile; the same info, the same Install. */
  @Builder
  newCard(item: MarketItem) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        IconTile({ icon: itemIcon(item), tileSize: 42, iconSize: 22 })
        Column({ space: 4 }) {
          Text(item.name)
            .fontSize(17)
            .fontWeight(700)
            .fontColor(Palette.text)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          OriginChip({
            text: item.id.startsWith('example:') ? 'Comes with the app' : 'From the marketplace',
            kind: item.id.startsWith('example:') ? 'phone' : 'community'
          })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      if (item.description.length > 0) {
        Text(item.description)
          .fontSize(14)
          .fontColor(Palette.text2)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      Flex({ wrap: FlexWrap.Wrap }) {
        if (item.widget) {
          Chip({ text: 'Widget', icon: $r('sys.symbol.square_grid_2x2') })
            .margin({ right: 6, bottom: 6 })
        }
        if (item.installs > 0) {
          Chip({ text: `${item.installs} installs`, fill: Palette.softButton, color: Palette.text3 })
            .margin({ right: 6, bottom: 6 })
        }
        ForEach(item.tags.slice(0, 3), (t: string) => {
          Chip({ text: t, fill: Palette.softButton, color: Palette.text3 })
            .margin({ right: 6, bottom: 6 })
        }, (t: string) => t)
      }
      .width('100%')
      PrimaryButton({ label: 'Install', buttonHeight: 44, onTap: () => this.onInstall(item) })
    }
    .width('100%')
    .padding(16)
    .borderRadius(22)
    .backgroundColor(Palette.surface)
  }

  @Builder
  placeholderTile() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Column().width(42).height(42).borderRadius(Radius.iconTile).backgroundColor(Palette.track)
        Column().layoutWeight(1).height(18).borderRadius(9).backgroundColor(Palette.track)
      }
      .width('100%')
      Column().width('80%').height(12).borderRadius(6).backgroundColor(Palette.track)
      Column().width('100%').height(44).borderRadius(Radius.button).backgroundColor(Palette.softButton)
    }
    .width('100%')
    .padding(16)
    .borderRadius(22)
    .backgroundColor(Palette.surface)
  }

  /** Redesign (NEW_MARKET): the same search, categories, list and paging as content(), restyled. */
  @Builder
  newContent() {
    Column({ space: 12 }) {
      Search({ value: this.q, placeholder: 'Search capsules' })
        .height(48)
        .borderRadius(14)
        .backgroundColor(Palette.surface)
        .border({ width: 1, color: Palette.inputBorder })
        .onChange((v: string) => {
          this.q = v;
        })
        .onSubmit(() => this.load(false))
      Scroll() {
        Row({ space: 8 }) {
          ForEach(MARKET_CATEGORIES, (c: string) => {
            Text(c.charAt(0).toUpperCase() + c.substring(1))
              .fontSize(15)
              .fontWeight(600)
              .fontColor(this.tag === c ? Palette.surface : Palette.text)
              .height(44)
              .padding({ left: 16, right: 16 })
              .borderRadius(22)
              .backgroundColor(this.tag === c ? Palette.blue : Palette.surface)
              .border(this.tag === c ? { width: 0 } : { width: 1, color: Palette.inputBorder })
              .onClick(() => {
                this.tag = this.tag === c ? '' : c;
                this.load(false);
              })
          }, (c: string) => c)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      if (this.onDeviceOnly) {
        this.onDeviceNote()
      } else if (this.offline) {
        Text(this.client.configured ? "The marketplace is offline right now. These examples come with the app." :
          'These examples come with the app.')
          .fontSize(13)
          .fontWeight(500)
          .fontColor(Palette.text2)
          .width('100%')
      }
      if (this.loading && this.items.length === 0) {
        Column({ space: 10 }) {
          this.placeholderTile()
          this.placeholderTile()
        }
        .width('100%')
      } else if (this.items.length === 0) {
        Text('Nothing found. Try another word.')
          .fontSize(15)
          .fontColor(Palette.text2)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(24)
      } else {
        List({ space: 10 }) {
          ForEach(this.items, (item: MarketItem) => {
            ListItem() {
              this.newCard(item)
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
        .contentEndOffset(this.embedded ? 120 : 0)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8 })
  }

  @Builder
  body() {
    if (Flags.NEW_MARKET) {
      this.newContent()
    } else {
      this.content()
    }
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
          this.body()
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
    } else {
      NavDestination() {
        this.body()
      }
      .title('Marketplace')
      .backgroundColor($r('sys.color.background_secondary'))
    }
  }
}
