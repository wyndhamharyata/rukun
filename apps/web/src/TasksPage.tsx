import { useVirtualizer } from '@tanstack/react-virtual'
import { useEffect, useMemo, useRef } from 'react'
import { useFirstRows } from './bench'
import { members, toDateText, type Task } from './data'
import { Avatar, Checkbox } from './parts'

type Props = {
  tasks: Task[]
  query: string
  newTask: string
  selected: string
  onQuery: (query: string) => void
  onNewTask: (text: string) => void
  onAddTask: () => void
  onSelect: (id: string) => void
  onToggle: (id: string) => void
}

export function TasksPage(props: Props) {
  const list = useRef<HTMLDivElement>(null)

  // Each task's title and assignee's name in lower case, for the search.
  const lowered = useMemo(
    () => props.tasks.map((task) => [task.title.toLowerCase(), members.get(task.assignee)!.name.toLowerCase()]),
    [props.tasks],
  )
  const shown = useMemo(() => {
    const needle = props.query.toLowerCase()
    return props.tasks.filter((_, index) => lowered[index].some((text) => text.includes(needle)))
  }, [props.tasks, lowered, props.query])

  const virtualizer = useVirtualizer({
    count: shown.length,
    getScrollElement: () => list.current,
    estimateSize: () => 34,
    paddingEnd: 12,
  })

  // A new search, or a new task, goes back to the top.
  useEffect(() => virtualizer.scrollToOffset(0), [props.query, props.tasks.length, virtualizer])
  useFirstRows(list, virtualizer.getVirtualItems().length > 0)

  return (
    <div className="page tasks">
      <div className="header">
        <h1>Tasks</h1>
        <input
          className="field new-task"
          placeholder="New task #space"
          value={props.newTask}
          onChange={(event) => props.onNewTask(event.target.value)}
          onKeyDown={(event) => event.key === 'Enter' && !event.nativeEvent.isComposing && props.onAddTask()}
        />
        <input
          className="field"
          placeholder="Search"
          value={props.query}
          onChange={(event) => props.onQuery(event.target.value)}
        />
      </div>
      <div className="columns">
        <span />
        <span className="cell">Title</span>
        <span className="cell">Space</span>
        <span className="cell">Assignee</span>
        <span className="cell end">Due</span>
      </div>
      {shown.length === 0 ? (
        <div className="empty">No tasks match</div>
      ) : (
        <div className="list" ref={list}>
          <div style={{ height: virtualizer.getTotalSize(), position: 'relative' }}>
            {virtualizer.getVirtualItems().map((row) => {
              const task = shown[row.index]
              return (
                <div
                  key={task.id}
                  className={task.id === props.selected ? 'row selected' : 'row'}
                  style={{ transform: `translateY(${row.start}px)` }}
                  onClick={() => props.onSelect(task.id)}
                >
                  <Checkbox round done={task.done} onToggle={() => props.onToggle(task.id)} />
                  <span className={task.done ? 'cell dim' : 'cell'}>{task.title}</span>
                  <span className="cell dim">#{task.space}</span>
                  <span className="assignee">
                    <Avatar member={task.assignee} size={20} />
                    <span className="cell dim">{members.get(task.assignee)!.name}</span>
                  </span>
                  <span className="cell dim end">{toDateText(task.due)}</span>
                </div>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}
