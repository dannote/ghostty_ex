interface ViewHook {
  el: HTMLElement
  pushEvent(event: string, payload: object): void
  pushEventTo(target: string, event: string, payload: object): void
  handleEvent(event: string, callback: (payload: never) => void): void
}

type ViewHookObject = ThisType<ViewHook> & {
  mounted?(): void
  destroyed?(): void
}
