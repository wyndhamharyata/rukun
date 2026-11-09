import raw from '../../../data/rukun.json'

export type Member = { id: string; name: string; avatar: string }
export type Entry = { text: string; done: boolean }
export type Item = {
  id: string
  author: string
  time: string
  kind: 'message' | 'task' | 'list' | 'note'
  text?: string
  photo?: string
  task?: string
  note?: string
  title?: string
  entries?: Entry[]
}
export type Space = { id: string; name: string; items: Item[] }
export type Task = {
  id: string
  title: string
  space: string
  assignee: string
  done: boolean
  due: string
}
export type Note = {
  id: string
  title: string
  space: string
  body: string[]
  checklist: Entry[]
  tasks: string[]
  links: string[]
  in_spaces: string[]
  in_notes: string[]
}

export const rukun = raw as unknown as {
  members: Member[]
  spaces: Space[]
  tasks: Task[]
  notes: Note[]
}

// Nadia, who writes the messages and tasks the app adds.
export const USER = 'm1'

export const members = new Map(rukun.members.map((member) => [member.id, member]))
export const notes = new Map(rukun.notes.map((note) => [note.id, note]))

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

// 2027-01-30 reads 30 Jan 2027.
export function toDateText(date: string) {
  const [year, month, day] = date.split('-')
  return `${Number(day)} ${MONTHS[Number(month) - 1]} ${year}`
}

// 2026-11-08T21:26 reads 8 Nov 2026, 21.26.
export function toTimeText(time: string) {
  return `${toDateText(time.slice(0, 10))}, ${time.slice(11, 13)}.${time.slice(14, 16)}`
}

// The local time now, as the data writes times.
export function nowText() {
  const now = new Date()
  const pad = (value: number) => String(value).padStart(2, '0')
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`
}

let added = 0

// An id for an added message or task, such as i+3, which no id in the data has.
export function makeId(prefix: string) {
  added += 1
  return `${prefix}+${added}`
}
