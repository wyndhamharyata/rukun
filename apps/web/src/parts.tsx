import check from './check.svg'
import { members, type Entry } from './data'

// A round checkbox for a task, or a square one for a checklist entry.
export function Checkbox(props: { done: boolean; round?: boolean; onToggle: () => void }) {
  const shape = props.round ? 'checkbox round' : 'checkbox'
  return (
    <button
      className={props.done ? `${shape} done` : shape}
      onClick={(event) => {
        event.stopPropagation()
        props.onToggle()
      }}
    >
      {props.done && <img src={check} alt="" />}
    </button>
  )
}

export function Avatar(props: { member: string; size: 20 | 28 }) {
  const member = members.get(props.member)!
  return <img className={`avatar size${props.size}`} src={`avatars/${member.avatar}`} alt="" />
}

export function EntryRow(props: { entry: Entry; done: boolean; onToggle: () => void }) {
  return (
    <div className="entry">
      <Checkbox done={props.done} onToggle={props.onToggle} />
      <span className={props.done ? 'cell dim' : 'cell'}>{props.entry.text}</span>
    </div>
  )
}
