use serde::Deserialize;

#[derive(Deserialize)]
pub struct Member {
    pub id: String,
    pub name: String,
    pub avatar: String,
}

#[derive(Deserialize, Clone)]
pub struct Entry {
    pub text: String,
    pub done: bool,
}

#[derive(Deserialize)]
pub struct Item {
    pub id: String,
    pub author: String,
    pub time: String,
    pub kind: String,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub photo: String,
    #[serde(default)]
    pub task: String,
    #[serde(default)]
    pub note: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub entries: Vec<Entry>,
}

#[derive(Deserialize)]
pub struct Space {
    pub id: String,
    pub name: String,
    pub items: Vec<Item>,
}

#[derive(Deserialize)]
pub struct Task {
    pub id: String,
    pub title: String,
    pub space: String,
    pub assignee: String,
    pub done: bool,
    pub due: String,
}

#[derive(Deserialize)]
pub struct Note {
    pub id: String,
    pub title: String,
    pub space: String,
    pub body: Vec<String>,
    pub checklist: Vec<Entry>,
    pub tasks: Vec<String>,
    pub links: Vec<String>,
    pub in_spaces: Vec<String>,
    pub in_notes: Vec<String>,
}

#[derive(Deserialize)]
pub struct Data {
    pub members: Vec<Member>,
    pub spaces: Vec<Space>,
    pub tasks: Vec<Task>,
    pub notes: Vec<Note>,
}

/// The data, built into the binary as the spec asks.
pub fn load() -> Data {
    serde_json::from_str(include_str!("../../../data/rukun.json")).expect("rukun.json parses")
}

/// Nadia, who writes the messages and tasks the app adds.
pub const USER: &str = "m1";

const MONTHS: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

/// 2027-01-30 reads 30 Jan 2027.
pub fn to_date_text(date: &str) -> String {
    let month: usize = date[5..7].parse().unwrap_or(1);
    let day: u32 = date[8..10].parse().unwrap_or(1);
    format!("{day} {} {}", MONTHS[month - 1], &date[..4])
}

/// 2026-11-08T21:26 reads 8 Nov 2026, 21.26.
pub fn to_time_text(time: &str) -> String {
    format!("{}, {}.{}", to_date_text(&time[..10]), &time[11..13], &time[14..16])
}

/// The local time now, as the data writes times.
pub fn now_text() -> String {
    chrono::Local::now().format("%Y-%m-%dT%H:%M").to_string()
}
