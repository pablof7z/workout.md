//! Coach tool set: rig.rs `Tool` implementations for the five coach actions
//! defined by the product spec. Every tool is a thin shim — side effects
//! live in the Swift app's `WorkoutSession`, so `call()` never touches
//! Workout.md state directly. Instead it hands `(name, args_json)` to the
//! `CoachHost` callback the app provided for this turn and returns whatever
//! string the host gives back as the tool result fed to the model.

use std::sync::Arc;

use rig::completion::ToolDefinition;
use rig::tool::Tool;
use serde::{Deserialize, Serialize};
use serde_json::json;

use super::CoachHost;

/// Error returned by a coach tool call. Coach tools only fail on malformed
/// arguments or JSON encoding trouble — the host call itself is infallible
/// from Rust's point of view (a UniFFI callback interface method cannot
/// return an FFI-level error here; the host encodes failures in the result
/// string it returns).
#[derive(Debug, thiserror::Error)]
#[error("coach tool error: {0}")]
pub struct ToolCallError(String);

fn route_to_host(
    host: &Arc<dyn CoachHost>,
    name: &str,
    args: &impl Serialize,
) -> Result<String, ToolCallError> {
    let args_json = serde_json::to_string(args).map_err(|e| ToolCallError(e.to_string()))?;
    Ok(host.apply_tool(name.to_string(), args_json))
}

// ---------------------------------------------------------------------
// adjust_set
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct AdjustSetArgs {
    pub exercise: String,
    pub set_index: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub new_weight: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub new_reps: Option<u32>,
}

#[derive(Clone)]
pub struct AdjustSetTool {
    host: Arc<dyn CoachHost>,
}

impl AdjustSetTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for AdjustSetTool {
    const NAME: &'static str = "adjust_set";
    type Error = ToolCallError;
    type Args = AdjustSetArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "Adjust the weight and/or rep target of a specific set in the \
                athlete's current workout. Use when a load or rep change is warranted mid-session \
                (e.g. the athlete reported a set felt too easy or too hard). Omit a field to leave \
                it unchanged."
                .to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "exercise": {
                        "type": "string",
                        "description": "Exercise name exactly as it appears in the plan"
                    },
                    "set_index": {
                        "type": "integer",
                        "description": "Zero-based index of the set within the exercise"
                    },
                    "new_weight": {
                        "type": "number",
                        "description": "New weight for the set, in the athlete's configured unit"
                    },
                    "new_reps": {
                        "type": "integer",
                        "description": "New target rep count for the set"
                    }
                },
                "required": ["exercise", "set_index"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

// ---------------------------------------------------------------------
// skip_set
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct SkipSetArgs {
    pub exercise: String,
    pub set_index: u32,
}

#[derive(Clone)]
pub struct SkipSetTool {
    host: Arc<dyn CoachHost>,
}

impl SkipSetTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for SkipSetTool {
    const NAME: &'static str = "skip_set";
    type Error = ToolCallError;
    type Args = SkipSetArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "Mark a specific set as skipped for the rest of this session. Use \
                when the athlete cannot or should not perform it (pain, equipment unavailable, \
                out of time)."
                .to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "exercise": {
                        "type": "string",
                        "description": "Exercise name exactly as it appears in the plan"
                    },
                    "set_index": {
                        "type": "integer",
                        "description": "Zero-based index of the set within the exercise"
                    }
                },
                "required": ["exercise", "set_index"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

// ---------------------------------------------------------------------
// deload_exercise
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DeloadExerciseArgs {
    pub exercise: String,
    pub weeks: u32,
}

#[derive(Clone)]
pub struct DeloadExerciseTool {
    host: Arc<dyn CoachHost>,
}

impl DeloadExerciseTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for DeloadExerciseTool {
    const NAME: &'static str = "deload_exercise";
    type Error = ToolCallError;
    type Args = DeloadExerciseArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "Schedule a deload (reduced load/volume block) for an exercise over \
                the given number of upcoming weeks. Use when fatigue, a stalled plateau, or \
                nagging pain call for backing off rather than pushing forward."
                .to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "exercise": {
                        "type": "string",
                        "description": "Exercise name exactly as it appears in the plan"
                    },
                    "weeks": {
                        "type": "integer",
                        "description": "Number of upcoming weeks the deload should cover"
                    }
                },
                "required": ["exercise", "weeks"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

// ---------------------------------------------------------------------
// add_note
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct AddNoteArgs {
    pub scope: String,
    pub text: String,
}

#[derive(Clone)]
pub struct AddNoteTool {
    host: Arc<dyn CoachHost>,
}

impl AddNoteTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for AddNoteTool {
    const NAME: &'static str = "add_note";
    type Error = ToolCallError;
    type Args = AddNoteArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "Attach a short note to the session, an exercise, or the plan for \
                future reference. Use for observations worth remembering that don't warrant a \
                plan change."
                .to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "scope": {
                        "type": "string",
                        "description": "What the note is about: a session, an exercise name, or \
                            the overall plan"
                    },
                    "text": {
                        "type": "string",
                        "description": "The note text, terse and factual"
                    }
                },
                "required": ["scope", "text"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

// ---------------------------------------------------------------------
// edit_plan
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct EditPlanArgs {
    pub instruction: String,
}

#[derive(Clone)]
pub struct EditPlanTool {
    host: Arc<dyn CoachHost>,
}

impl EditPlanTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for EditPlanTool {
    const NAME: &'static str = "edit_plan";
    type Error = ToolCallError;
    type Args = EditPlanArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "Request a structural change to the training plan beyond a single \
                set or exercise (e.g. swap an exercise, change the weekly split, add/remove a \
                day). State the change as a plain instruction; the host applies it."
                .to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "instruction": {
                        "type": "string",
                        "description": "Plain-language instruction describing the plan change"
                    }
                },
                "required": ["instruction"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// Records every `apply_tool` call it receives and echoes back a fixed
    /// response, so tests can assert both the routed arguments and the
    /// tool's handling of the host's return value.
    struct RecordingHost {
        calls: Mutex<Vec<(String, String)>>,
        response: String,
    }

    impl RecordingHost {
        fn new(response: impl Into<String>) -> Self {
            Self {
                calls: Mutex::new(Vec::new()),
                response: response.into(),
            }
        }
    }

    impl CoachHost for RecordingHost {
        fn apply_tool(&self, name: String, args_json: String) -> String {
            self.calls.lock().unwrap().push((name, args_json));
            self.response.clone()
        }
    }

    #[tokio::test]
    async fn adjust_set_routes_args_to_host_and_returns_its_response() {
        let host = Arc::new(RecordingHost::new("applied"));
        let tool = AdjustSetTool::new(host.clone());

        let result = tool
            .call(AdjustSetArgs {
                exercise: "Back Squat".to_string(),
                set_index: 2,
                new_weight: Some(102.5),
                new_reps: None,
            })
            .await
            .expect("adjust_set call should succeed");

        assert_eq!(result, "applied");
        let calls = host.calls.lock().unwrap();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].0, "adjust_set");
        let parsed: serde_json::Value = serde_json::from_str(&calls[0].1).unwrap();
        assert_eq!(parsed["exercise"], "Back Squat");
        assert_eq!(parsed["set_index"], 2);
        assert_eq!(parsed["new_weight"], 102.5);
        assert!(parsed.get("new_reps").is_none());
    }

    #[tokio::test]
    async fn skip_set_routes_expected_shape() {
        let host = Arc::new(RecordingHost::new("skipped"));
        let tool = SkipSetTool::new(host.clone());

        let result = tool
            .call(SkipSetArgs {
                exercise: "Overhead Press".to_string(),
                set_index: 0,
            })
            .await
            .expect("skip_set call should succeed");

        assert_eq!(result, "skipped");
        let calls = host.calls.lock().unwrap();
        assert_eq!(calls[0].0, "skip_set");
        let parsed: serde_json::Value = serde_json::from_str(&calls[0].1).unwrap();
        assert_eq!(parsed["exercise"], "Overhead Press");
        assert_eq!(parsed["set_index"], 0);
    }

    #[tokio::test]
    async fn deload_exercise_routes_expected_shape() {
        let host = Arc::new(RecordingHost::new("deloaded"));
        let tool = DeloadExerciseTool::new(host.clone());

        let result = tool
            .call(DeloadExerciseArgs {
                exercise: "Deadlift".to_string(),
                weeks: 2,
            })
            .await
            .expect("deload_exercise call should succeed");

        assert_eq!(result, "deloaded");
        let parsed: serde_json::Value =
            serde_json::from_str(&host.calls.lock().unwrap()[0].1).unwrap();
        assert_eq!(parsed["exercise"], "Deadlift");
        assert_eq!(parsed["weeks"], 2);
    }

    #[tokio::test]
    async fn add_note_routes_expected_shape() {
        let host = Arc::new(RecordingHost::new("noted"));
        let tool = AddNoteTool::new(host.clone());

        let result = tool
            .call(AddNoteArgs {
                scope: "session".to_string(),
                text: "Left knee felt tight on warmup sets.".to_string(),
            })
            .await
            .expect("add_note call should succeed");

        assert_eq!(result, "noted");
        let parsed: serde_json::Value =
            serde_json::from_str(&host.calls.lock().unwrap()[0].1).unwrap();
        assert_eq!(parsed["scope"], "session");
        assert_eq!(parsed["text"], "Left knee felt tight on warmup sets.");
    }

    #[tokio::test]
    async fn edit_plan_routes_expected_shape() {
        let host = Arc::new(RecordingHost::new("edited"));
        let tool = EditPlanTool::new(host.clone());

        let result = tool
            .call(EditPlanArgs {
                instruction: "Swap Front Squat for Back Squat on lower days.".to_string(),
            })
            .await
            .expect("edit_plan call should succeed");

        assert_eq!(result, "edited");
        let parsed: serde_json::Value =
            serde_json::from_str(&host.calls.lock().unwrap()[0].1).unwrap();
        assert_eq!(
            parsed["instruction"],
            "Swap Front Squat for Back Squat on lower days."
        );
    }

    #[test]
    fn adjust_set_args_reject_missing_required_fields() {
        let bad: Result<AdjustSetArgs, _> = serde_json::from_str(r#"{"exercise":"Bench"}"#);
        assert!(bad.is_err(), "set_index is required and must be rejected");
    }

    #[test]
    fn adjust_set_args_parse_with_only_optional_fields_present() {
        let args: AdjustSetArgs =
            serde_json::from_str(r#"{"exercise":"Bench","set_index":1,"new_reps":8}"#)
                .expect("new_weight is optional and may be omitted");
        assert_eq!(args.new_weight, None);
        assert_eq!(args.new_reps, Some(8));
    }
}
