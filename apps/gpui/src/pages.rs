use gpui_kit::component::input::{Input, InputState};
use gpui_kit::prelude::*;
use gpui_kit::*;

use crate::app::*;
use crate::data::{to_date_text, to_time_text};

const SEMIBOLD: FontWeight = FontWeight::SEMIBOLD;

fn id(text: impl Into<SharedString>) -> ElementId {
    ElementId::Name(text.into())
}

/// One line of text that ends in an ellipsis, sharing a row's width by grow.
fn cell(text: impl Into<SharedString>, grow: f32, color: u32) -> Div {
    div()
        .flex_grow(grow)
        .flex_basis(px(0.))
        .min_w_0()
        .truncate()
        .text_color(rgb(color))
        .child(text.into())
}

/// A border of a width that GPUI's border methods do not name.
fn with_border(mut element: Stateful<Div>, width: f32, color: Rgba) -> Stateful<Div> {
    let widths = &mut element.style().border_widths;
    widths.top = Some(px(width).into());
    widths.right = Some(px(width).into());
    widths.bottom = Some(px(width).into());
    widths.left = Some(px(width).into());
    element.border_color(color)
}

/// A round checkbox for a task, or a square one for a checklist entry.
fn checkbox(id_text: impl Into<SharedString>, done: bool, round: bool) -> Stateful<Div> {
    let side = if round { 16. } else { 14. };
    let check = if round { 10. } else { 9. };
    let element = div()
        .id(id(id_text))
        .flex_none()
        .size(px(side))
        .flex()
        .items_center()
        .justify_center()
        .rounded(px(if round { side / 2. } else { 4. }));

    if done {
        element.bg(rgb(ACCENT)).child(svg().path("rukun/check.svg").size(px(check)).text_color(white()))
    } else {
        with_border(element, 1.5, rgb(FAINT))
    }
}

/// An image cropped to fill its box. The box shows the empty colour until the image decodes.
fn image(path: std::path::PathBuf, width: f32, height: f32, radius: f32) -> Div {
    div()
        .flex_none()
        .w(px(width))
        .h(px(height))
        .rounded(px(radius))
        .bg(rgb(EMPTY))
        .child(img(path).size_full().rounded(px(radius)).object_fit(ObjectFit::Cover))
}

fn heading(text: impl Into<SharedString>) -> Div {
    div()
        .flex_1()
        .min_w_0()
        .truncate()
        .text_size(px(28.))
        .line_height(px(36.))
        .font_weight(FontWeight::BOLD)
        .child(text.into())
}

/// A text field: GPUI Kit's input without its own look, in the spec's box.
fn field(state: &Entity<InputState>, width: Option<f32>, height: f32, radius: f32, inset: f32, window: &Window, cx: &App) -> Div {
    let is_focused = state.read(cx).focus_handle(cx).is_focused(window);
    let element = div()
        .flex_none()
        .flex()
        .items_center()
        .h(px(height))
        .rounded(px(radius))
        .bg(rgba(HOVER))
        .border_1()
        .border_color(if is_focused { rgba(FOCUS) } else { rgba(0) })
        // Input keeps 10 points of its own on each side, even without its look. The margin puts
        // the text inset from the box's edge, past its 1-point border.
        .child(Input::new(state).appearance(false).text_size(px(13.)).mx(px(inset - 1. - 10.)));

    match width {
        Some(width) => element.w(px(width)),
        None => element.w_full(),
    }
}

impl Rukun {
    pub fn render_sidebar(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let mut sidebar = div()
            .id("sidebar")
            .flex()
            .flex_col()
            .flex_none()
            .w(px(220.))
            .h_full()
            .pt(px(52.))
            .px(px(12.))
            .pb(px(12.))
            .gap(px(2.))
            .bg(rgb(SIDEBAR))
            .overflow_y_scroll()
            .child(self.nav_row("tasks", "Tasks".into(), cx))
            .child(div().flex_none().h(px(1.)).my(px(6.)).bg(rgb(LINE)));

        for space in &self.data.spaces {
            sidebar = sidebar.child(self.nav_row(&space.id, format!("#{}", space.name), cx));
        }

        sidebar
    }

    fn nav_row(&self, space: &str, label: String, cx: &mut Context<Self>) -> impl IntoElement {
        let is_current = self.section == space;
        let space = space.to_string();
        let background = if is_current { SELECTED } else { HOVER };

        div()
            .id(id(format!("nav {space}")))
            .flex()
            .flex_none()
            .items_center()
            .h(px(32.))
            .px(px(12.))
            .rounded(px(6.))
            .font_weight(FontWeight::MEDIUM)
            .text_color(rgb(if is_current { TEXT } else { DIM }))
            .when(is_current, |row| row.bg(rgba(SELECTED)))
            .hover(move |style| style.bg(rgba(background)))
            .child(div().truncate().child(label))
            .on_click(cx.listener(move |this, _, _, cx| {
                this.open_space(&space);
                cx.notify();
            }))
    }

    pub fn render_tasks_page(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let header = div()
            .flex()
            .flex_none()
            .items_center()
            .gap(px(8.))
            .h(px(36.))
            .child(heading("Tasks"))
            .child(field(&self.new_task, Some(280.), 28., 6., 10., window, cx))
            .child(field(&self.search, Some(240.), 28., 6., 10., window, cx));

        let columns = div()
            .flex()
            .flex_none()
            .items_center()
            .gap(px(16.))
            .h(px(28.))
            .mt(px(16.))
            .px(px(12.))
            .border_b_1()
            .border_color(rgb(LINE))
            .text_size(px(12.))
            .line_height(px(16.))
            .font_weight(SEMIBOLD)
            .child(div().flex_none().w(px(16.)))
            .child(cell("Title", 5., FAINT))
            .child(cell("Space", 2., FAINT))
            .child(cell("Assignee", 2., FAINT))
            .child(div().flex_none().w(px(88.)).text_right().text_color(rgb(FAINT)).child("Due"));

        let list = if self.shown.is_empty() {
            div()
                .flex()
                .flex_1()
                .items_center()
                .justify_center()
                .text_color(rgb(DIM))
                .child("No tasks match")
                .into_any_element()
        } else {
            uniform_list(
                "tasks",
                self.shown.len(),
                cx.processor(|this, range: std::ops::Range<usize>, _window, cx| {
                    range.map(|row| this.render_task_row(this.shown[row], cx)).collect::<Vec<_>>()
                }),
            )
            .track_scroll(&self.tasks_scroll)
            .flex_1()
            .pb(px(12.))
            .into_any_element()
        };

        div()
            .flex()
            .flex_col()
            .flex_1()
            .min_w_0()
            .pt(px(40.))
            .px(px(24.))
            .child(header)
            .child(columns)
            .child(list)
    }

    fn render_task_row(&self, index: usize, cx: &mut Context<Self>) -> AnyElement {
        let task = &self.data.tasks[index];
        let is_selected = self.selected == task.id;
        let background = if is_selected { SELECTED_ROW } else { HOVER };
        let select_id = task.id.clone();
        let toggle_id = task.id.clone();

        // uniform_list sizes a row to its content unless the row asks for the list's width.
        div()
            .id(id(task.id.clone()))
            .w_full()
            .flex()
            .items_center()
            .gap(px(16.))
            .h(px(34.))
            .px(px(12.))
            .rounded(px(6.))
            .when(is_selected, |row| row.bg(rgba(SELECTED_ROW)))
            .hover(move |style| style.bg(rgba(background)))
            .on_click(cx.listener(move |this, _, _, cx| {
                this.selected = select_id.clone();
                cx.notify();
            }))
            .child(checkbox(format!("{} done", task.id), task.done, true).on_click(cx.listener(
                move |this, _, _, cx| {
                    cx.stop_propagation();
                    this.toggle_task(&toggle_id);
                    cx.notify();
                },
            )))
            .child(cell(task.title.clone(), 5., if task.done { DIM } else { TEXT }))
            .child(cell(format!("#{}", task.space), 2., DIM))
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(8.))
                    .flex_grow(2.)
                    .flex_basis(px(0.))
                    .min_w_0()
                    .child(image(self.avatar_path(&task.assignee), 20., 20., 10.))
                    .child(div().min_w_0().truncate().text_color(rgb(DIM)).child(self.member_name(&task.assignee).to_string())),
            )
            .child(div().flex_none().w(px(88.)).text_right().text_color(rgb(DIM)).child(to_date_text(&task.due)))
            .into_any_element()
    }

    pub fn render_space_page(&mut self, space: usize, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let timeline = self.timeline(space);
        let name = self.data.spaces[space].name.clone();

        if self.composer_space != name {
            self.composer_space = name.clone();
            let placeholder = format!("Message #{name}");
            self.composer.update(cx, |state, cx| state.set_placeholder(placeholder, window, cx));
        }

        div()
            .flex()
            .flex_col()
            .flex_1()
            .min_w_0()
            .pt(px(40.))
            .px(px(24.))
            .pb(px(24.))
            .child(div().flex().flex_none().items_center().h(px(36.)).child(heading(format!("#{name}"))))
            .child(
                list(
                    timeline,
                    cx.processor(move |this, index: usize, _window, cx| this.render_item(space, index, cx)),
                )
                .flex_1()
                .mt(px(8.))
                .pb(px(16.)),
            )
            .child(div().flex_none().mt(px(12.)).child(field(&self.composer, None, 40., 8., 12., window, cx)))
    }

    /// One item of a timeline. Its top padding is the gap above it, so the first item's is the
    /// timeline's own padding.
    fn render_item(&self, space: usize, index: usize, cx: &mut Context<Self>) -> AnyElement {
        let item = &self.data.spaces[space].items[index];
        let content = match item.kind.as_str() {
            "task" => self.render_task_card(&item.task, cx),
            "list" => self.render_list_card(space, index, cx),
            "note" => self.render_note_card(&item.id, &item.note, cx),
            _ => {
                let mut message = div().flex().flex_col().gap(px(8.)).child(div().child(item.text.clone()));
                if !item.photo.is_empty() {
                    message = message.child(image(self.resources.join("photos").join(&item.photo), 240., 180., 8.));
                }
                message.into_any_element()
            }
        };

        div()
            .flex()
            .gap(px(12.))
            .pt(px(16.))
            .child(image(self.avatar_path(&item.author), 28., 28., 14.))
            .child(
                div()
                    .flex()
                    .flex_col()
                    .flex_1()
                    .min_w_0()
                    .max_w(px(640.))
                    .gap(px(4.))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.))
                            .child(div().font_weight(SEMIBOLD).child(self.member_name(&item.author).to_string()))
                            .child(
                                div()
                                    .text_size(px(12.))
                                    .line_height(px(16.))
                                    .text_color(rgb(FAINT))
                                    .child(to_time_text(&item.time)),
                            ),
                    )
                    .child(content),
            )
            .into_any_element()
    }

    fn card(&self) -> Div {
        div().w(px(360.)).rounded(px(8.)).bg(rgba(CARD)).border_1().border_color(rgb(LINE))
    }

    fn render_task_card(&self, task_id: &str, cx: &mut Context<Self>) -> AnyElement {
        let task = &self.data.tasks[self.task_index[task_id]];
        let toggle_id = task.id.clone();

        self.card()
            .flex()
            .items_center()
            .gap(px(10.))
            .h(px(40.))
            .px(px(11.))
            .child(checkbox(format!("{} card", task.id), task.done, true).on_click(cx.listener(
                move |this, _, _, cx| {
                    this.toggle_task(&toggle_id);
                    cx.notify();
                },
            )))
            .child(div().flex_1().min_w_0().truncate().text_color(rgb(if task.done { DIM } else { TEXT })).child(task.title.clone()))
            .child(image(self.avatar_path(&task.assignee), 20., 20., 10.))
            .into_any_element()
    }

    fn render_list_card(&self, space: usize, index: usize, cx: &mut Context<Self>) -> AnyElement {
        let item = &self.data.spaces[space].items[index];
        let mut card = self
            .card()
            .flex()
            .flex_col()
            .p(px(11.))
            .child(div().font_weight(SEMIBOLD).mb(px(6.)).truncate().child(item.title.clone()));

        for (entry_index, entry) in item.entries.iter().enumerate() {
            let toggle = cx.listener(move |this, _, _, cx| {
                let entry = &mut this.data.spaces[space].items[index].entries[entry_index];
                entry.done = !entry.done;
                cx.notify();
            });
            card = card.child(entry_row(format!("{} {entry_index}", item.id), &entry.text, entry.done, toggle));
        }

        card.into_any_element()
    }

    fn render_note_card(&self, item_id: &str, note_id: &str, cx: &mut Context<Self>) -> AnyElement {
        let note = &self.data.notes[self.note_index[note_id]];
        let open_id = note.id.clone();

        div()
            .id(id(item_id.to_string()))
            .w(px(360.))
            .h(px(56.))
            .flex()
            .flex_col()
            .justify_center()
            .gap(px(2.))
            .px(px(11.))
            .rounded(px(8.))
            .bg(rgba(CARD))
            .border_1()
            .border_color(rgb(LINE))
            .hover(|style| style.bg(rgba(HOVER)))
            .on_click(cx.listener(move |this, _, _, cx| {
                this.open_note(&open_id);
                cx.notify();
            }))
            .child(div().font_weight(SEMIBOLD).truncate().child(note.title.clone()))
            .when(!note.body.is_empty(), |card| {
                card.child(
                    div()
                        .truncate()
                        .text_size(px(12.))
                        .line_height(px(16.))
                        .text_color(rgb(DIM))
                        .child(note.body[0].clone()),
                )
            })
            .into_any_element()
    }

    pub fn render_note_page(&mut self, note: usize, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let note = &self.data.notes[note];
        let note_id = note.id.clone();
        let mut content = div()
            .flex()
            .flex_col()
            .max_w(px(640.))
            .child(div().truncate().text_size(px(28.)).line_height(px(36.)).font_weight(FontWeight::BOLD).child(note.title.clone()))
            .child(div().flex().flex_col().gap(px(12.)).mt(px(16.)).children(note.body.iter().map(|text| div().child(text.clone()))));

        if !note.checklist.is_empty() {
            content = content.child(section_title("Checklist"));
            for (entry_index, entry) in note.checklist.iter().enumerate() {
                let note_index = self.note_index[&note.id];
                let toggle = cx.listener(move |this, _, _, cx| {
                    let entry = &mut this.data.notes[note_index].checklist[entry_index];
                    entry.done = !entry.done;
                    cx.notify();
                });
                content = content.child(entry_row(format!("{} {entry_index}", note.id), &entry.text, entry.done, toggle));
            }
        }

        if !note.tasks.is_empty() {
            content = content.child(section_title("Tasks"));
            for task_id in &note.tasks {
                let task = &self.data.tasks[self.task_index[task_id]];
                let toggle_id = task.id.clone();
                content = content.child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(16.))
                        .h(px(34.))
                        .px(px(12.))
                        .child(checkbox(format!("{} note", task.id), task.done, true).on_click(cx.listener(
                            move |this, _, _, cx| {
                                this.toggle_task(&toggle_id);
                                cx.notify();
                            },
                        )))
                        .child(cell(task.title.clone(), 1., if task.done { DIM } else { TEXT }))
                        .child(div().flex_none().w(px(88.)).text_right().text_color(rgb(DIM)).child(to_date_text(&task.due))),
                );
            }
        }

        if !note.links.is_empty() {
            content = content.child(section_title("Links"));
            for link_id in &note.links {
                let title = self.data.notes[self.note_index[link_id]].title.clone();
                let open_id = link_id.clone();
                content = content.child(link(format!("link {link_id}"), title).on_click(cx.listener(
                    move |this, _, _, cx| {
                        this.open_note(&open_id);
                        cx.notify();
                    },
                )));
            }
        }

        if !note.in_spaces.is_empty() || !note.in_notes.is_empty() {
            content = content.child(section_title("Mentioned in"));
            for space_id in &note.in_spaces {
                let open_id = space_id.clone();
                content = content.child(link(format!("space {space_id}"), format!("#{space_id}")).on_click(cx.listener(
                    move |this, _, _, cx| {
                        this.open_space(&open_id);
                        cx.notify();
                    },
                )));
            }
            for other_id in &note.in_notes {
                let title = self.data.notes[self.note_index[other_id]].title.clone();
                let open_id = other_id.clone();
                content = content.child(link(format!("note {other_id}"), title).on_click(cx.listener(
                    move |this, _, _, cx| {
                        this.open_note(&open_id);
                        cx.notify();
                    },
                )));
            }
        }

        // The id is the note's, so each note opens at its top.
        div()
            .id(id(format!("note page {note_id}")))
            .flex_1()
            .min_w_0()
            .overflow_y_scroll()
            .pt(px(40.))
            .px(px(24.))
            .pb(px(24.))
            .child(content)
    }
}

fn section_title(title: &'static str) -> Div {
    div()
        .mt(px(24.))
        .mb(px(8.))
        .text_size(px(15.))
        .line_height(px(20.))
        .font_weight(SEMIBOLD)
        .child(title)
}

fn link(id_text: String, label: String) -> Stateful<Div> {
    div()
        .id(id(id_text))
        .flex()
        .items_center()
        .h(px(28.))
        .text_color(rgb(ACCENT))
        .child(div().truncate().child(label))
}

fn entry_row(
    id_text: String,
    text: &str,
    done: bool,
    toggle: impl Fn(&ClickEvent, &mut Window, &mut App) + 'static,
) -> Div {
    div()
        .flex()
        .items_center()
        .gap(px(8.))
        .h(px(24.))
        .child(checkbox(id_text, done, false).on_click(toggle))
        .child(div().min_w_0().truncate().text_color(rgb(if done { DIM } else { TEXT })).child(text.to_string()))
}
