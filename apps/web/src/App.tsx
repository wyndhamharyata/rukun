import { useMemo, useState } from 'react'
import { makeId, notes, nowText, rukun, USER, type Entry, type Item, type Task } from './data'
import { host } from './host'
import { NotePage } from './NotePage'
import { SpacePage } from './SpacePage'
import { TasksPage } from './TasksPage'

export default function App() {
  const [tasks, setTasks] = useState(rukun.tasks)
  const [spaces, setSpaces] = useState(rukun.spaces)
  // Checklist entries ticked or unticked, by item or note id and the entry's place.
  const [entries, setEntries] = useState<Record<string, boolean>>({})
  // "tasks", or the id of the space the sidebar shows as current.
  const [section, setSection] = useState(host.settings.page || 'tasks')
  const [noteId, setNoteId] = useState('')
  const [selected, setSelected] = useState('')
  const [query, setQuery] = useState('')
  const [newTask, setNewTask] = useState('')
  const [draft, setDraft] = useState('')

  const tasksById = useMemo(() => new Map(tasks.map((task) => [task.id, task])), [tasks])
  const entryDone = (key: string, entry: Entry) => entries[key] ?? entry.done

  const toggleTask = (id: string) =>
    setTasks((all) => all.map((task) => (task.id === id ? { ...task, done: !task.done } : task)))
  const toggleEntry = (key: string, done: boolean) => setEntries((all) => ({ ...all, [key]: !done }))

  const addItem = (spaceId: string, item: Item) =>
    setSpaces((all) => all.map((space) => (space.id === spaceId ? { ...space, items: [...space.items, item] } : space)))

  const openNote = (id: string) => {
    setNoteId(id)
    setSection(notes.get(id)!.space)
  }
  const openSpace = (id: string) => {
    setNoteId('')
    setSection(id)
  }

  // The first #name that names a space puts the task there, and every such #name leaves the
  // title. With no title left, nothing is added.
  const addTask = () => {
    let spaceId = 'keluarga'
    let isPicked = false
    const words: string[] = []

    for (const word of newTask.split(/\s+/).filter(Boolean)) {
      const named = word.startsWith('#') && spaces.some((space) => space.id === word.slice(1))
      if (!named) words.push(word)
      else if (!isPicked) {
        spaceId = word.slice(1)
        isPicked = true
      }
    }

    if (words.length === 0) return

    const now = nowText()
    const task: Task = { id: makeId('t'), title: words.join(' '), space: spaceId, assignee: USER, done: false, due: now.slice(0, 10) }
    setTasks((all) => [task, ...all])
    addItem(spaceId, { id: makeId('i'), author: USER, time: now, kind: 'task', task: task.id })
    setSelected(task.id)
    setNewTask('')
  }

  const send = (spaceId: string) => {
    const text = draft.trim()
    if (text === '') return

    addItem(spaceId, { id: makeId('i'), author: USER, time: nowText(), kind: 'message', text })
    setDraft('')
  }

  const space = spaces.find((item) => item.id === section)

  return (
    <div className="window">
      <div className="titlebar" data-tauri-drag-region />
      <nav className="sidebar">
        <div className={section === 'tasks' ? 'nav current' : 'nav'} onClick={() => openSpace('tasks')}>
          Tasks
        </div>
        <div className="divider" />
        {spaces.map((item) => (
          <div key={item.id} className={section === item.id ? 'nav current' : 'nav'} onClick={() => openSpace(item.id)}>
            #{item.name}
          </div>
        ))}
      </nav>
      {noteId !== '' ? (
        <NotePage
          note={notes.get(noteId)!}
          tasks={tasksById}
          entryDone={entryDone}
          onToggleTask={toggleTask}
          onToggleEntry={toggleEntry}
          onOpenNote={openNote}
          onOpenSpace={openSpace}
        />
      ) : space === undefined ? (
        <TasksPage
          tasks={tasks}
          query={query}
          newTask={newTask}
          selected={selected}
          onQuery={setQuery}
          onNewTask={setNewTask}
          onAddTask={addTask}
          onSelect={setSelected}
          onToggle={toggleTask}
        />
      ) : (
        // The key gives each space its own list, so each opens at its end.
        <SpacePage
          key={space.id}
          space={space}
          tasks={tasksById}
          entryDone={entryDone}
          draft={draft}
          onDraft={setDraft}
          onSend={() => send(space.id)}
          onToggleTask={toggleTask}
          onToggleEntry={toggleEntry}
          onOpenNote={openNote}
        />
      )}
    </div>
  )
}
