import { notes, toDateText, type Entry, type Note, type Task } from './data'
import { Checkbox, EntryRow } from './parts'

type Props = {
  note: Note
  tasks: Map<string, Task>
  entryDone: (key: string, entry: Entry) => boolean
  onToggleTask: (id: string) => void
  onToggleEntry: (key: string, done: boolean) => void
  onOpenNote: (id: string) => void
  onOpenSpace: (id: string) => void
}

export function NotePage(props: Props) {
  const note = props.note
  const mentions = note.in_spaces.length + note.in_notes.length

  return (
    // The key opens each note at its top.
    <div className="note-page" key={note.id}>
      <div className="note-content">
        <h1>{note.title}</h1>
        <div className="paragraphs">
          {note.body.map((paragraph, index) => (
            <p key={index}>{paragraph}</p>
          ))}
        </div>
        {note.checklist.length > 0 && (
          <section>
            <h2>Checklist</h2>
            {note.checklist.map((entry, index) => {
              const key = `${note.id}:${index}`
              const done = props.entryDone(key, entry)
              return <EntryRow key={index} entry={entry} done={done} onToggle={() => props.onToggleEntry(key, done)} />
            })}
          </section>
        )}
        {note.tasks.length > 0 && (
          <section>
            <h2>Tasks</h2>
            {note.tasks.map((id) => {
              const task = props.tasks.get(id)!
              return (
                <div className="note-task" key={id}>
                  <Checkbox round done={task.done} onToggle={() => props.onToggleTask(id)} />
                  <span className={task.done ? 'cell dim' : 'cell'}>{task.title}</span>
                  <span className="cell dim end">{toDateText(task.due)}</span>
                </div>
              )
            })}
          </section>
        )}
        {note.links.length > 0 && (
          <section>
            <h2>Links</h2>
            {note.links.map((id) => (
              <div className="link cell" key={id} onClick={() => props.onOpenNote(id)}>
                {notes.get(id)!.title}
              </div>
            ))}
          </section>
        )}
        {mentions > 0 && (
          <section>
            <h2>Mentioned in</h2>
            {note.in_spaces.map((id) => (
              <div className="link cell" key={`space ${id}`} onClick={() => props.onOpenSpace(id)}>
                #{id}
              </div>
            ))}
            {note.in_notes.map((id) => (
              <div className="link cell" key={`note ${id}`} onClick={() => props.onOpenNote(id)}>
                {notes.get(id)!.title}
              </div>
            ))}
          </section>
        )}
      </div>
    </div>
  )
}
