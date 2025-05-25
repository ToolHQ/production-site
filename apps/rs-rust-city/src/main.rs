// rustycity/src/main.rs

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts, EguiPlugin};
use bevy_rapier2d::prelude::*;
use rand::Rng;

// === COMPONENTES ===
#[derive(Component)]
struct Player;

#[derive(Component)]
struct PoliceCar;

#[derive(Component)]
struct TrafficLight {
    is_green: bool,
    timer: f32,
    direction: LaneDirection,
}

#[derive(Component)]
struct NpcCar {
    direction: Vec2,
    lane: LaneDirection,
    next_turn_timer: f32,
    braking: bool,
    style: DrivingStyle,
}

#[derive(Component)]
struct TrafficSpawner {
    position: Vec2,
    direction: Vec2,
    lane: LaneDirection,
    cooldown: f32,
    timer: f32,
}

#[derive(Component, Clone, Copy, PartialEq, Eq)]
enum LaneDirection {
    NorthSouth,
    EastWest,
}

#[derive(Component)]
struct Civilian {
    scared: bool,
}

#[derive(Component)]
struct SafeZone {
    radius: f32,
}

#[derive(Component)]
struct PoliceHelicopter;

#[derive(Component)]
struct RoadBlock;

#[derive(Component)]
enum EscapeType {
    Helicopter,
    Tunnel,
    Sewer,
}

#[derive(Component)]
struct EscapePoint {
    kind: EscapeType,
    countdown: f32,
}

// === ESTADOS ===
#[derive(Resource)]
struct PlayerPenalty {
    infractions: u32,
    last_infraction_time: f32,
}

#[derive(Resource)]
struct PoliceState {
    active: bool,
}

#[derive(Resource)]
struct WantedLevel {
    stars: u8,
    cooldown_timer: f32,
}

#[derive(Resource)]
struct ArrestState {
    arrested: bool,
    timer: f32,
    prison_position: Vec2,
}

#[derive(Resource)]
struct HidingTimer {
    timer: f32,
}

#[derive(Clone, Copy, PartialEq)]
enum DrivingStyle {
    Cautious,
    Normal,
    Aggressive,
}

// === MAIN ===
fn main() {
    App::new()
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "RustyCity".into(),
                resolution: (1280., 720.).into(),
                ..default()
            }),
            ..default()
        }))
        .add_plugins(RapierPhysicsPlugin::<NoUserData>::pixels_per_meter(100.0))
        .add_plugins(EguiPlugin)
        .insert_resource(PlayerPenalty {
            infractions: 0,
            last_infraction_time: 0.0,
        })
        .insert_resource(WantedLevel {
            stars: 0,
            cooldown_timer: 0.0,
        })
        .insert_resource(PoliceState { active: false })
        .insert_resource(ArrestState {
            arrested: false,
            timer: 0.0,
            prison_position: Vec2::ZERO,
        })
        .insert_resource(HidingTimer { timer: 0.0 })
        .add_startup_system(setup)
        .add_startup_system(spawn_civilians)
        .add_system(civilian_panic_system)
        .add_system(civilian_reports_police)
        .add_system(handle_surrender)
        .add_system(prison_timer)
        .add_system(show_arrest_hud)
        .add_system(handle_prison_escape)
        .add_startup_system(spawn_safe_zone)
        .add_system(check_hide_from_police)
        .add_system(show_hiding_status)
        .add_system(decay_wanted_level)
        .add_system(escalate_police_response)
        .add_system(show_wanted_hud)
        .add_system(detect_red_light_violation)
        .add_startup_system(spawn_prison)
        .add_startup_system(spawn_helicopter_once)
        .add_system(helicopter_follow_player)
        .add_system(spawn_road_blocks)
        .add_system(spawn_escape_point)
        .add_system(handle_escape_logic)
        .add_system(show_escape_hud)
        .run();
}

fn setup(mut commands: Commands) {
    commands.spawn(Camera2dBundle::default());
    // Aqui você chama todos os spawns adicionais (player, semáforos, prisões, NPCs, etc)
}

// Os sistemas (civilian_panic_system, etc.) devem ser definidos abaixo ou em módulos separados
