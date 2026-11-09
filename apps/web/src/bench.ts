import { useEffect, type RefObject } from 'react'
import { host } from './host'

const POINTS_PER_SECOND = 1500
const DELAY_MS = 1000

let isStarted = false

// For the page the app opens on: once its rows are drawn, the next frame prints first-frame, and a
// second later the bench scrolls the list, when the harness asks for them.
export function useFirstRows(list: RefObject<HTMLElement | null>, hasRows: boolean) {
  useEffect(() => {
    if (!hasRows || isStarted || !list.current) return
    isStarted = true
    const element = list.current

    // The second callback runs once the frame with the rows is on screen.
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        if (host.settings.mark) host.print('first-frame')
        if (host.settings.scroll) setTimeout(() => scroll(element), DELAY_MS)
      }),
    )
  }, [list, hasRows])
}

// Scrolls at 1,500 points a second towards the far end, turning back at each end. Each frame's
// start time sets the place. When the time is up, prints each frame's start in microseconds since
// the scroll began, then done, and quits.
function scroll(element: HTMLElement) {
  const starts: number[] = []
  let begin = -1
  let from = 0
  let direction = 1

  function step(now: number) {
    const max = element.scrollHeight - element.clientHeight

    if (begin < 0) {
      begin = now
      from = element.scrollTop
      direction = from < max / 2 ? 1 : -1
    }

    const seconds = (now - begin) / 1000
    starts.push(now - begin)

    if (seconds >= host.settings.scrollSeconds) {
      const lines = starts.map((start) => `frame ${Math.round(start * 1000)}`)
      host.print([...lines, 'done'].join('\n'))
      host.quit()
      return
    }

    element.scrollTop = toBounced(from + direction * POINTS_PER_SECOND * seconds, max)
    requestAnimationFrame(step)
  }

  requestAnimationFrame(step)
}

// Folds a position into 0 to max, as a ball that bounces between the two ends.
export function toBounced(position: number, max: number) {
  const period = 2 * max
  const folded = ((position % period) + period) % period
  return folded <= max ? folded : period - folded
}
