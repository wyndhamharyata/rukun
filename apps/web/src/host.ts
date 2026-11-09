// The settings the harness passes to the app, and the way back to the shell's stdout. Electron's
// preload and Tauri's initialization script each set window.testapp before the page runs.

export type Settings = {
  page: string
  mark: boolean
  scroll: boolean
  scrollSeconds: number
}

type Host = {
  settings: Settings
  print: (text: string) => void
  quit: () => void
}

declare global {
  interface Window {
    testapp?: Host
  }
}

// In a plain browser, during development, nothing is measured.
export const host: Host = window.testapp ?? {
  settings: { page: '', mark: false, scroll: false, scrollSeconds: 20 },
  print: (text) => console.log(text),
  quit: () => {},
}
