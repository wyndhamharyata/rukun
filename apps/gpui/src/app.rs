use std::collections::HashMap;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use gpui_kit::component::input::{InputEvent, InputState};
use gpui_kit::*;

use crate::data::{self, Data, Item, Task, USER};

pub const WINDOW: u32 = 0x121214;
pub const SIDEBAR: u32 = 0x161618;
pub const CARD: u32 = 0xffffff0a;
pub const LINE: u32 = 0x2e2e33;
pub const TEXT: u32 = 0xf2f2f4;
pub const DIM: u32 = 0xacacb4;
pub const FAINT: u32 = 0x8a8a93;
pub const HOVER: u32 = 0xffffff12;
pub const SELECTED: u32 = 0xffffff1a;
pub const ACCENT: u32 = 0x0a84ff;
pub const FOCUS: u32 = 0x0a84ff8a;
pub const SELECTED_ROW: u32 = 0x0a84ff2e;
pub const EMPTY: u32 = 0x2a2a2f;

const BENCH_POINTS_PER_SECOND: f32 = 1500.;
const BENCH_DELAY: Duration = Duration::from_secs(1);

/// The harness's settings, from the test app spec.
pub struct Settings {
    pub page: String,
    pub mark: bool,
    pub scroll: bool,
    pub scroll_seconds: f32,
}

impl Settings {
    fn read() -> Self {
        let get = |name: &str| std::env::var(name).unwrap_or_default();
        Self {
            page: get("TESTAPP_PAGE"),
            mark: get("TESTAPP_MARK") == "1",
            scroll: get("TESTAPP_SCROLL") == "1",
            scroll_seconds: get("TESTAPP_SCROLL_SECONDS").parse().unwrap_or(20.),
        }
    }
}

/// The bench scroll: where it began, which way it goes, and each frame's start since.
struct Bench {
    start: Instant,
    from: f32,
    direction: f32,
    frames: Vec<Duration>,
}

pub struct Rukun {
    pub data: Data,
    pub task_index: HashMap<String, usize>,
    pub note_index: HashMap<String, usize>,
    pub member_index: HashMap<String, usize>,
    /// Each task's title and assignee's name in lower case, for the search.
    lowered: Vec<(String, String)>,
    /// The tasks the search shows, by their place in data.tasks.
    pub shown: Vec<usize>,
    /// "tasks", or the id of the space the sidebar shows as current.
    pub section: String,
    pub note: Option<String>,
    pub selected: String,
    pub search: Entity<InputState>,
    pub new_task: Entity<InputState>,
    pub composer: Entity<InputState>,
    /// The space whose name the composer's placeholder holds.
    pub composer_space: String,
    pub tasks_scroll: UniformListScrollHandle,
    pub timelines: HashMap<String, ListState>,
    pub resources: PathBuf,
    settings: Settings,
    is_marked: bool,
    bench: Option<Bench>,
    added: usize,
    _subscriptions: Vec<Subscription>,
}

impl Rukun {
    pub fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let search = cx.new(|cx| InputState::new(window, cx).placeholder("Search"));
        let new_task = cx.new(|cx| InputState::new(window, cx).placeholder("New task #space"));
        let composer = cx.new(|cx| InputState::new(window, cx));

        let subscriptions = vec![
            cx.subscribe_in(&search, window, |this, state, event, _, cx| {
                if matches!(event, InputEvent::Change) {
                    this.filter_tasks(&state.read(cx).value());
                    this.tasks_scroll.scroll_to_item(0, ScrollStrategy::Top);
                }
                cx.notify();
            }),
            cx.subscribe_in(&new_task, window, |this, _, event, window, cx| {
                if matches!(event, InputEvent::PressEnter { .. }) {
                    this.add_task(window, cx);
                }
                cx.notify();
            }),
            cx.subscribe_in(&composer, window, |this, _, event, window, cx| {
                if matches!(event, InputEvent::PressEnter { .. }) {
                    this.send(window, cx);
                }
                cx.notify();
            }),
        ];

        let settings = Settings::read();
        let section = if settings.page.is_empty() { "tasks".into() } else { settings.page.clone() };
        let mut rukun = Self {
            data: data::load(),
            task_index: HashMap::new(),
            note_index: HashMap::new(),
            member_index: HashMap::new(),
            lowered: Vec::new(),
            shown: Vec::new(),
            section,
            note: None,
            selected: String::new(),
            search,
            new_task,
            composer,
            composer_space: String::new(),
            tasks_scroll: UniformListScrollHandle::new(),
            timelines: HashMap::new(),
            resources: resource_folder(),
            settings,
            is_marked: false,
            bench: None,
            added: 0,
            _subscriptions: subscriptions,
        };

        for (index, note) in rukun.data.notes.iter().enumerate() {
            rukun.note_index.insert(note.id.clone(), index);
        }
        for (index, member) in rukun.data.members.iter().enumerate() {
            rukun.member_index.insert(member.id.clone(), index);
        }
        rukun.index_tasks("");
        rukun
    }

    pub fn member_name(&self, id: &str) -> &str {
        &self.data.members[self.member_index[id]].name
    }

    pub fn avatar_path(&self, id: &str) -> PathBuf {
        let member = &self.data.members[self.member_index[id]];
        self.resources.join("avatars").join(&member.avatar)
    }

    fn index_tasks(&mut self, query: &str) {
        self.task_index.clear();
        self.lowered.clear();

        for (index, task) in self.data.tasks.iter().enumerate() {
            self.task_index.insert(task.id.clone(), index);
            let name = self.data.members[self.member_index[&task.assignee]].name.to_lowercase();
            self.lowered.push((task.title.to_lowercase(), name));
        }

        self.filter_tasks(query);
    }

    fn filter_tasks(&mut self, query: &str) {
        let needle = query.to_lowercase();
        self.shown = (0..self.lowered.len())
            .filter(|&index| {
                let (title, name) = &self.lowered[index];
                title.contains(&needle) || name.contains(&needle)
            })
            .collect();
    }

    pub fn toggle_task(&mut self, id: &str) {
        let index = self.task_index[id];
        self.data.tasks[index].done = !self.data.tasks[index].done;
    }

    pub fn open_space(&mut self, id: &str) {
        self.note = None;
        self.section = id.to_string();
        // A space opens at its end, and follows it while it is there.
        if let Some(timeline) = self.timelines.get(id) {
            timeline.set_follow_mode(FollowMode::Tail);
        }
    }

    pub fn open_note(&mut self, id: &str) {
        self.section = self.data.notes[self.note_index[id]].space.clone();
        self.note = Some(id.to_string());
    }

    /// The timeline of a space, made the first time the space shows.
    pub fn timeline(&mut self, space: usize) -> ListState {
        let space = &self.data.spaces[space];
        self.timelines
            .entry(space.id.clone())
            .or_insert_with(|| {
                let state = ListState::new(space.items.len(), ListAlignment::Top, px(200.));
                state.set_follow_mode(FollowMode::Tail);
                state
            })
            .clone()
    }

    fn make_id(&mut self, prefix: &str) -> String {
        self.added += 1;
        format!("{prefix}+{}", self.added)
    }

    fn push_item(&mut self, space_id: &str, item: Item) {
        let space = self.data.spaces.iter_mut().find(|space| space.id == space_id).unwrap();
        space.items.push(item);
        let count = space.items.len();

        if let Some(timeline) = self.timelines.get(space_id) {
            timeline.splice(count - 1..count - 1, 1);
            timeline.scroll_to_end();
        }
    }

    /// The first #name that names a space puts the task there, and every such #name leaves the
    /// title. With no title left, nothing is added.
    fn add_task(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let text = self.new_task.read(cx).value().to_string();
        let mut space = "keluarga".to_string();
        let mut is_picked = false;
        let mut words = Vec::new();

        for word in text.split_whitespace() {
            let named = word.strip_prefix('#').filter(|name| self.data.spaces.iter().any(|space| space.id == *name));
            match named {
                None => words.push(word),
                Some(name) if !is_picked => {
                    space = name.to_string();
                    is_picked = true;
                }
                Some(_) => {}
            }
        }

        if words.is_empty() {
            return;
        }

        let now = data::now_text();
        let task = Task {
            id: self.make_id("t"),
            title: words.join(" "),
            space: space.clone(),
            assignee: USER.into(),
            done: false,
            due: now[..10].to_string(),
        };
        let item = Item {
            id: self.make_id("i"),
            author: USER.into(),
            time: now,
            kind: "task".into(),
            text: String::new(),
            photo: String::new(),
            task: task.id.clone(),
            note: String::new(),
            title: String::new(),
            entries: Vec::new(),
        };

        self.selected = task.id.clone();
        self.data.tasks.insert(0, task);
        self.push_item(&space, item);
        let query = self.search.read(cx).value().to_string();
        self.index_tasks(&query);
        self.tasks_scroll.scroll_to_item(0, ScrollStrategy::Top);
        self.new_task.update(cx, |state, cx| state.set_value("", window, cx));
    }

    fn send(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let text = self.composer.read(cx).value().trim().to_string();
        if text.is_empty() {
            return;
        }

        let item = Item {
            id: self.make_id("i"),
            author: USER.into(),
            time: data::now_text(),
            kind: "message".into(),
            text,
            photo: String::new(),
            task: String::new(),
            note: String::new(),
            title: String::new(),
            entries: Vec::new(),
        };
        let space = self.section.clone();
        self.push_item(&space, item);
        self.composer.update(cx, |state, cx| state.set_value("", window, cx));
    }

    /// For the page the app opens on. The frame after the first draws prints first-frame, and a
    /// second later the bench scrolls the page's list, when the harness asks for them.
    fn mark_first_frame(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.is_marked {
            return;
        }
        self.is_marked = true;

        cx.on_next_frame(window, |this, window, cx| {
            if this.settings.mark {
                println!("first-frame");
            }
            if this.settings.scroll {
                cx.spawn_in(window, async move |this, cx| {
                    cx.background_executor().timer(BENCH_DELAY).await;
                    this.update_in(cx, |this, window, cx| this.bench_step(window, cx)).ok();
                })
                .detach();
            }
        });
    }

    /// One frame of the bench: from the frame callback, the place the time since the start asks
    /// for. When the time is up, prints each frame's start in microseconds since the scroll began,
    /// then done, and quits.
    fn bench_step(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let now = Instant::now();
        let (offset, max) = self.bench_scroll_place();

        let bench = self.bench.get_or_insert_with(|| Bench {
            start: now,
            from: offset,
            direction: if offset < max / 2. { 1. } else { -1. },
            frames: Vec::new(),
        });
        let elapsed = now - bench.start;
        bench.frames.push(elapsed);

        if elapsed.as_secs_f32() >= self.settings.scroll_seconds {
            let mut lines: Vec<String> =
                bench.frames.iter().map(|frame| format!("frame {}", frame.as_micros())).collect();
            lines.push("done".into());
            println!("{}", lines.join("\n"));
            cx.quit();
            return;
        }

        let place = bench.from + bench.direction * BENCH_POINTS_PER_SECOND * elapsed.as_secs_f32();
        self.set_bench_scroll(to_bounced(place, max));
        cx.notify();
        cx.on_next_frame(window, |this, window, cx| this.bench_step(window, cx));
    }

    /// The scroll of the page's list, and its largest, in points.
    fn bench_scroll_place(&self) -> (f32, f32) {
        match self.timelines.get(&self.section).filter(|_| self.section != "tasks") {
            Some(timeline) => (
                -f32::from(timeline.scroll_px_offset_for_scrollbar().y),
                f32::from(timeline.max_offset_for_scrollbar().y),
            ),
            None => {
                let handle = &self.tasks_scroll.0.borrow().base_handle;
                (-f32::from(handle.offset().y), f32::from(handle.max_offset().y))
            }
        }
    }

    fn set_bench_scroll(&self, place: f32) {
        match self.timelines.get(&self.section).filter(|_| self.section != "tasks") {
            Some(timeline) => timeline.set_offset_from_scrollbar(point(px(0.), px(-place))),
            None => self.tasks_scroll.0.borrow().base_handle.set_offset(point(px(0.), px(-place))),
        }
    }
}

impl Render for Rukun {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let page = match (&self.note, self.section.as_str()) {
            (Some(note), _) => {
                let note = self.note_index[note];
                self.render_note_page(note, window, cx).into_any_element()
            }
            (None, "tasks") => self.render_tasks_page(window, cx).into_any_element(),
            (None, section) => {
                let space = self.data.spaces.iter().position(|space| space.id == section).unwrap_or(0);
                self.render_space_page(space, window, cx).into_any_element()
            }
        };

        self.mark_first_frame(window, cx);

        div()
            .flex()
            .size_full()
            .bg(rgb(WINDOW))
            .text_color(rgb(TEXT))
            .font_family(".SystemUIFont")
            .text_size(px(13.))
            .line_height(px(18.))
            .child(self.render_sidebar(cx))
            .child(page)
    }
}

/// Folds a place into 0 to max, as a ball that bounces between the two ends.
pub fn to_bounced(place: f32, max: f32) -> f32 {
    let period = 2. * max;
    let folded = place.rem_euclid(period);
    if folded <= max { folded } else { period - folded }
}

/// Contents/Resources in the .app, or the research repository's data/ folder in a build.
fn resource_folder() -> PathBuf {
    let executable = std::env::current_exe().unwrap_or_default();
    if let Some(contents) = executable.parent().and_then(|folder| folder.parent()) {
        let resources = contents.join("Resources");
        if resources.join("photos").exists() {
            return resources;
        }
    }
    PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../../data"))
}
