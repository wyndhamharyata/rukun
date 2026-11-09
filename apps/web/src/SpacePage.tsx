import { useVirtualizer } from '@tanstack/react-virtual'
import { useLayoutEffect, useRef } from 'react'
import { useFirstRows } from './bench'
import { members, notes, toTimeText, type Entry, type Item, type Space, type Task } from './data'
import { Avatar, Checkbox, EntryRow } from './parts'

type Props = {
  space: Space
  tasks: Map<string, Task>
  entryDone: (key: string, entry: Entry) => boolean
  draft: string
  onDraft: (text: string) => void
  onSend: () => void
  onToggleTask: (id: string) => void
  onToggleEntry: (key: string, done: boolean) => void
  onOpenNote: (id: string) => void
}

// A guess at an item's height before it is measured: a name line and two lines of text.
const ITEM_ESTIMATE = 60

export function SpacePage(props: Props) {
  const list = useRef<HTMLDivElement>(null)
  const items = props.space.items
  const virtualizer = useVirtualizer({
    count: items.length,
    getScrollElement: () => list.current,
    estimateSize: () => ITEM_ESTIMATE,
    gap: 16,
    paddingStart: 16,
    paddingEnd: 16,
    // Scrolling to the last item keeps the bottom padding in view.
    scrollPaddingEnd: 16,
  })

  // The page opens at the end of the timeline, and a sent message brings it back there.
  useLayoutEffect(() => {
    virtualizer.scrollToIndex(items.length - 1, { align: 'end' })
  }, [items.length, virtualizer])

  const shown = virtualizer.getVirtualItems()
  useFirstRows(list, shown.some((row) => row.index === items.length - 1))

  return (
    <div className="page space">
      <div className="header">
        <h1>#{props.space.name}</h1>
      </div>
      <div className="timeline" ref={list}>
        <div style={{ height: virtualizer.getTotalSize(), position: 'relative' }}>
          {shown.map((row) => (
            <div
              key={items[row.index].id}
              className="item"
              data-index={row.index}
              ref={virtualizer.measureElement}
              style={{ transform: `translateY(${row.start}px)` }}
            >
              <TimelineItem {...props} item={items[row.index]} />
            </div>
          ))}
        </div>
      </div>
      <input
        className="field composer"
        placeholder={`Message #${props.space.name}`}
        value={props.draft}
        onChange={(event) => props.onDraft(event.target.value)}
        onKeyDown={(event) => event.key === 'Enter' && !event.nativeEvent.isComposing && props.onSend()}
      />
    </div>
  )
}

function TimelineItem(props: Props & { item: Item }) {
  const item = props.item
  return (
    <>
      <Avatar member={item.author} size={28} />
      <div className="body">
        <div className="by">
          <b>{members.get(item.author)!.name}</b>
          <time>{toTimeText(item.time)}</time>
        </div>
        {item.kind === 'message' && (
          <div className="message">
            <p>{item.text}</p>
            {item.photo && <img className="photo" src={`photos/${item.photo}`} alt="" />}
          </div>
        )}
        {item.kind === 'task' && <TaskCard task={props.tasks.get(item.task!)!} onToggle={props.onToggleTask} />}
        {item.kind === 'list' && (
          <div className="card list-card">
            <b className="cell">{item.title}</b>
            {item.entries!.map((entry, index) => {
              const key = `${item.id}:${index}`
              const done = props.entryDone(key, entry)
              return <EntryRow key={index} entry={entry} done={done} onToggle={() => props.onToggleEntry(key, done)} />
            })}
          </div>
        )}
        {item.kind === 'note' && <NoteCard id={item.note!} onOpen={props.onOpenNote} />}
      </div>
    </>
  )
}

function TaskCard(props: { task: Task; onToggle: (id: string) => void }) {
  const task = props.task
  return (
    <div className="card task-card">
      <Checkbox round done={task.done} onToggle={() => props.onToggle(task.id)} />
      <span className={task.done ? 'cell dim' : 'cell'}>{task.title}</span>
      <Avatar member={task.assignee} size={20} />
    </div>
  )
}

function NoteCard(props: { id: string; onOpen: (id: string) => void }) {
  const note = notes.get(props.id)!
  return (
    <div className="card note-card" onClick={() => props.onOpen(note.id)}>
      <b className="cell">{note.title}</b>
      {note.body.length > 0 && <span className="cell small dim">{note.body[0]}</span>}
    </div>
  )
}
