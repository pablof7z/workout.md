//! Coach tool set: rig.rs `Tool` implementations for the general, composable
//! domain primitives defined by `docs/architecture/domain-primitives.md` §7.
//! Every tool is a thin shim — side effects live in the Swift app (a
//! `PlanRepository`/`MemoryStore`/`ActiveSessionStore`), so `call()` never
//! touches Workout.md state directly. Instead it hands `(name, args_json)`
//! to the `CoachHost` callback the app provided for this turn and returns
//! whatever string the host gives back as the tool result fed to the model.
//!
//! There is no per-tool business logic here. The value of this module is
//! the tool *name* plus the `definition()` description/schema that teaches
//! the model the operation vocabulary — especially `plan_apply`, the single
//! atomic plan-mutation primitive that replaces the old narrow tool family
//! (`adjust_set`/`skip_set`/`deload_exercise`/`add_note`/`edit_plan`).

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
// plan_get
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct PlanGetArgs {}

#[derive(Clone)]
pub struct PlanGetTool {
    host: Arc<dyn CoachHost>,
}

impl PlanGetTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for PlanGetTool {
    const NAME: &'static str = "plan_get";
    type Error = ToolCallError;
    type Args = PlanGetArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "Return the current training plan as a JSON snapshot (its stable \
                session/block/exercise/set UUIDs, ordering, and the cursor to the next \
                workout). Call this before editing so you can reference elements by their real \
                ids."
                .to_string(),
            parameters: json!({
                "type": "object",
                "properties": {},
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

// ---------------------------------------------------------------------
// plan_apply
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct PlanApplyArgs {
    pub operations: Vec<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub propose: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
}

#[derive(Clone)]
pub struct PlanApplyTool {
    host: Arc<dyn CoachHost>,
}

impl PlanApplyTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for PlanApplyTool {
    const NAME: &'static str = "plan_apply";
    type Error = ToolCallError;
    type Args = PlanApplyArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "The single plan-mutation tool. Apply (or propose) an ORDERED list \
                of operations to the training plan ATOMICALLY — all succeed or none are \
                applied. Use this for every plan change: creating a plan, importing a routine, \
                editing a future workout, replacing an exercise, reordering, or restructuring \
                the weekly split. Each operation in `operations` is a flat object with an \
                `\"op\"` discriminator, one of: setPlanMeta, addSession, updateSession, \
                removeSession, moveSession, setCursor, addBlock, updateBlock, removeBlock, \
                moveBlock, addExercise, updateExercise, replaceExercise, removeExercise, \
                moveExercise, addSet, updateSet, removeSet, moveSet. \
                \n\nAddressing is always by UUID string. For an add* op you supply the NEW \
                element's own uuid in its payload, and you may reuse that same uuid string as \
                the parent id in a LATER op of the same batch — this is how you build a whole \
                plan (session -> blocks -> exercises -> sets) in one atomic call. \
                \n\n`addBlock` carries a FULL block subtree, e.g. \
                {\"op\":\"addBlock\",\"sessionID\":\"<uuid>\",\"index\":0,\"block\":{\"id\":\"<uuid>\",\"kind\":\"straight\",\"label\":\"...\",\"rounds\":1,\"restSeconds\":null,\"exercises\":[{\"id\":\"<uuid>\",\"name\":\"Bench Press\",\"cue\":\"\",\"sets\":[{\"id\":\"<uuid>\",\"reps\":10,\"weight\":135,\"seconds\":null}]}]}}. \
                `kind` is one of straight|superset|circuit. Likewise `addExercise` carries a \
                full exercise (with its `sets` array) and `addSet` carries a full set. A set is \
                one of: reps (`reps` plus optional `weight`), an ordinary timed hold (`seconds`), \
                or a Tindeq force hold (`seconds`, `targetMinKg`, and `targetMaxKg`). For example, \
                a seven-second Tindeq half-crimp set targeting 30-34 kg is \
                {\"id\":\"<uuid>\",\"reps\":null,\"weight\":null,\"seconds\":7,\"targetMinKg\":30,\"targetMaxKg\":34}. \
                \n\nUpdate ops (`updateSession`/`updateBlock`/`updateExercise`/`updateSet`/ \
                `setPlanMeta`) use three-state fields: OMIT a field to leave it unchanged; pass \
                JSON `null` to clear it (only meaningful for optional targets); pass a value to \
                set it. `updateSet` supports `reps`, `weight`, `seconds`, `targetMinKg`, and \
                `targetMaxKg`. Example: {\"op\":\"updateSet\",\"id\":\"<uuid>\",\"reps\":null,\
                \"weight\":null,\"seconds\":7,\"targetMinKg\":30,\"targetMaxKg\":34} converts an \
                existing set into a Tindeq force hold. Clear both target bounds to convert a \
                Tindeq hold back to an ordinary timed hold. \
                \n\n`setCursor` {\"op\":\"setCursor\",\"sessionID\":\"<uuid or null>\"} chooses \
                which session is the next workout (there is no calendar). \
                \n\n`propose` (default false, apply-by-default): pass true to return the \
                change as an UNAPPLIED proposal for the athlete to preview/confirm rather than \
                applying it immediately. Only propose when you are explicitly iterating on \
                alternatives with the athlete; otherwise apply. \
                \n\nEnd-to-end example — creating a brand-new one-session plan is a single call \
                with two ops: first `{\"op\":\"addSession\",\"id\":\"S1\",\"name\":\"Upper A\",\"index\":0}`, \
                then `{\"op\":\"addBlock\",\"sessionID\":\"S1\",\"index\":0,\"block\":{...}}` \
                reusing the same session id."
                .to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "operations": {
                        "type": "array",
                        "items": { "type": "object" },
                        "description": "Ordered list of PlanOp objects, each with an \"op\" \
                            discriminator, applied atomically."
                    },
                    "propose": {
                        "type": "boolean",
                        "description": "If true, return an unapplied proposal instead of \
                            applying immediately. Defaults to false (apply)."
                    },
                    "summary": {
                        "type": "string",
                        "description": "Optional human-readable summary of the change, shown \
                            in revision history."
                    }
                },
                "required": ["operations"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

// ---------------------------------------------------------------------
// plan_revisions
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct PlanRevisionsArgs {}

#[derive(Clone)]
pub struct PlanRevisionsTool {
    host: Arc<dyn CoachHost>,
}

impl PlanRevisionsTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for PlanRevisionsTool {
    const NAME: &'static str = "plan_revisions";
    type Error = ToolCallError;
    type Args = PlanRevisionsArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "List restorable revisions of the current plan (id + summary + \
                timestamp). Each applied change creates one."
                .to_string(),
            parameters: json!({
                "type": "object",
                "properties": {},
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

// ---------------------------------------------------------------------
// plan_restore
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct PlanRestoreArgs {
    pub revision_id: String,
}

#[derive(Clone)]
pub struct PlanRestoreTool {
    host: Arc<dyn CoachHost>,
}

impl PlanRestoreTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for PlanRestoreTool {
    const NAME: &'static str = "plan_restore";
    type Error = ToolCallError;
    type Args = PlanRestoreArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "Restore a previous plan revision by id (itself recorded as a new \
                revision)."
                .to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "revision_id": {
                        "type": "string",
                        "description": "Id of the revision to restore, from plan_revisions"
                    }
                },
                "required": ["revision_id"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

// ---------------------------------------------------------------------
// memory_add
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct MemoryAddArgs {
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
}

#[derive(Clone)]
pub struct MemoryAddTool {
    host: Arc<dyn CoachHost>,
}

impl MemoryAddTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for MemoryAddTool {
    const NAME: &'static str = "memory_add";
    type Error = ToolCallError;
    type Args = MemoryAddArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "Record a durable, freeform memory about the athlete (any \
                coaching-relevant fact: goals, equipment, injuries, schedule, preferences, \
                disliked movements, progression rules, anything). Optional tags for retrieval."
                .to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "text": {
                        "type": "string",
                        "description": "The memory text, terse and factual"
                    },
                    "tags": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "Optional freeform tags for later retrieval"
                    }
                },
                "required": ["text"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

// ---------------------------------------------------------------------
// memory_update
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct MemoryUpdateArgs {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
}

#[derive(Clone)]
pub struct MemoryUpdateTool {
    host: Arc<dyn CoachHost>,
}

impl MemoryUpdateTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for MemoryUpdateTool {
    const NAME: &'static str = "memory_update";
    type Error = ToolCallError;
    type Args = MemoryUpdateArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "Edit an existing durable memory by id. Omit a field to leave it \
                unchanged."
                .to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "id": {
                        "type": "string",
                        "description": "Id of the memory to update, from memory_query"
                    },
                    "text": {
                        "type": "string",
                        "description": "New memory text; omit to leave unchanged"
                    },
                    "tags": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "New tag list (replaces the existing tags); omit to \
                            leave unchanged"
                    }
                },
                "required": ["id"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

// ---------------------------------------------------------------------
// memory_query
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct MemoryQueryArgs {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub query: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub limit: Option<u32>,
}

#[derive(Clone)]
pub struct MemoryQueryTool {
    host: Arc<dyn CoachHost>,
}

impl MemoryQueryTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for MemoryQueryTool {
    const NAME: &'static str = "memory_query";
    type Error = ToolCallError;
    type Args = MemoryQueryArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "Recall durable memories by substring and/or tags.".to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Substring to match against memory text; omit to skip \
                            text filtering"
                    },
                    "tags": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "Only return memories with at least one of these tags"
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of memories to return"
                    }
                },
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

// ---------------------------------------------------------------------
// memory_remove
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct MemoryRemoveArgs {
    pub id: String,
}

#[derive(Clone)]
pub struct MemoryRemoveTool {
    host: Arc<dyn CoachHost>,
}

impl MemoryRemoveTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for MemoryRemoveTool {
    const NAME: &'static str = "memory_remove";
    type Error = ToolCallError;
    type Args = MemoryRemoveArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "Delete a durable memory by id.".to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "id": {
                        "type": "string",
                        "description": "Id of the memory to delete, from memory_query"
                    }
                },
                "required": ["id"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

// ---------------------------------------------------------------------
// session_apply
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct SessionApplyArgs {
    pub operations: Vec<serde_json::Value>,
}

#[derive(Clone)]
pub struct SessionApplyTool {
    host: Arc<dyn CoachHost>,
}

impl SessionApplyTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for SessionApplyTool {
    const NAME: &'static str = "session_apply";
    type Error = ToolCallError;
    type Args = SessionApplyArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "Mutate the LIVE in-progress workout (only available when a session \
                is active): adjust a set's target, skip a set, substitute an exercise, or add a \
                set — addressing sets/exercises by their stable id from the live session \
                grounding. `operations` is an ordered list applied atomically. This changes the \
                active workout, NOT the plan — use plan_apply for future workouts. \
                \n\nOperation vocabulary: \
                `adjustSet` {\"op\":\"adjustSet\",\"setID\":\"<uuid>\",\"reps\":8,\"weight\":225} \
                (omit a field to leave it unchanged); \
                `skipSet` {\"op\":\"skipSet\",\"setID\":\"<uuid>\"}; \
                `substituteExercise` {\"op\":\"substituteExercise\",\"exerciseName\":\"...\",\"newName\":\"...\"}; \
                `addSet` {\"op\":\"addSet\",\"afterSetID\":\"<uuid>\",\"reps\":10,\"weight\":null}. \
                If an operation addresses an id that can't be resolved in the live session, the \
                host returns an error string for you to react to."
                .to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "operations": {
                        "type": "array",
                        "items": { "type": "object" },
                        "description": "Ordered list of SessionOp objects, each with an \"op\" \
                            discriminator, applied atomically to the live workout."
                    }
                },
                "required": ["operations"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        route_to_host(&self.host, Self::NAME, &args)
    }
}

// ---------------------------------------------------------------------
// escalate_to_reasoning
// ---------------------------------------------------------------------

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct EscalateToReasoningArgs {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

#[derive(Clone)]
pub struct EscalateToReasoningTool {
    host: Arc<dyn CoachHost>,
}

impl EscalateToReasoningTool {
    pub fn new(host: Arc<dyn CoachHost>) -> Self {
        Self { host }
    }
}

impl Tool for EscalateToReasoningTool {
    const NAME: &'static str = "escalate_to_reasoning";
    type Error = ToolCallError;
    type Args = EscalateToReasoningArgs;
    type Output = String;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: Self::NAME.to_string(),
            description: "Switch to the stronger reasoning model to work through a demanding \
                task — e.g. building a full training plan from a vague description, or a \
                complex multi-session repair. Call this as your ONLY action for the turn and do \
                NOT answer the user yourself; the reasoning model will take over and respond. \
                Use it sparingly — the fast model handles everyday coaching, quick set \
                adjustments, and chat."
                .to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "reason": {
                        "type": "string",
                        "description": "Optional short note on why this task needs the \
                            reasoning model"
                    }
                },
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
    async fn plan_get_routes_empty_args_and_returns_host_response() {
        let host = Arc::new(RecordingHost::new(r#"{"id":"plan-1","sessions":[]}"#));
        let tool = PlanGetTool::new(host.clone());

        let result = tool
            .call(PlanGetArgs::default())
            .await
            .expect("plan_get call should succeed");

        assert_eq!(result, r#"{"id":"plan-1","sessions":[]}"#);
        let calls = host.calls.lock().unwrap();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].0, "plan_get");
        assert_eq!(calls[0].1, "{}");
    }

    #[test]
    fn plan_get_args_deserialize_from_empty_object() {
        let args: PlanGetArgs = serde_json::from_str("{}").expect("plan_get args are all-optional");
        let _ = args;
    }

    #[tokio::test]
    async fn plan_apply_routes_operations_and_propose_flag() {
        let host = Arc::new(RecordingHost::new("applied"));
        let tool = PlanApplyTool::new(host.clone());

        let result = tool
            .call(PlanApplyArgs {
                operations: vec![
                    json!({"op": "addSession", "id": "11111111-1111-1111-1111-111111111111", "name": "Upper A", "index": 0}),
                    json!({"op": "addBlock", "sessionID": "11111111-1111-1111-1111-111111111111", "index": 0, "block": {"id": "22222222-2222-2222-2222-222222222222", "kind": "straight", "label": "", "rounds": 1, "restSeconds": null, "exercises": []}}),
                ],
                propose: Some(true),
                summary: Some("create Upper A".to_string()),
            })
            .await
            .expect("plan_apply call should succeed");

        assert_eq!(result, "applied");
        let calls = host.calls.lock().unwrap();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].0, "plan_apply");
        let parsed: serde_json::Value = serde_json::from_str(&calls[0].1).unwrap();
        assert_eq!(parsed["operations"].as_array().unwrap().len(), 2);
        assert_eq!(parsed["operations"][0]["op"], "addSession");
        assert_eq!(parsed["operations"][1]["op"], "addBlock");
        assert_eq!(parsed["propose"], true);
        assert_eq!(parsed["summary"], "create Upper A");
    }

    #[tokio::test]
    async fn plan_apply_omits_optional_fields_when_absent() {
        let host = Arc::new(RecordingHost::new("applied"));
        let tool = PlanApplyTool::new(host.clone());

        tool.call(PlanApplyArgs {
            operations: vec![json!({"op": "setCursor", "sessionID": serde_json::Value::Null})],
            propose: None,
            summary: None,
        })
        .await
        .expect("plan_apply call should succeed");

        let calls = host.calls.lock().unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&calls[0].1).unwrap();
        assert!(parsed.get("propose").is_none());
        assert!(parsed.get("summary").is_none());
    }

    #[tokio::test]
    async fn plan_revisions_routes_empty_args_and_returns_host_response() {
        let host = Arc::new(RecordingHost::new(r#"[{"id":"rev-1"}]"#));
        let tool = PlanRevisionsTool::new(host.clone());

        let result = tool
            .call(PlanRevisionsArgs::default())
            .await
            .expect("plan_revisions call should succeed");

        assert_eq!(result, r#"[{"id":"rev-1"}]"#);
        let calls = host.calls.lock().unwrap();
        assert_eq!(calls[0].0, "plan_revisions");
        assert_eq!(calls[0].1, "{}");
    }

    #[tokio::test]
    async fn plan_restore_routes_revision_id() {
        let host = Arc::new(RecordingHost::new("restored"));
        let tool = PlanRestoreTool::new(host.clone());

        let result = tool
            .call(PlanRestoreArgs {
                revision_id: "rev-42".to_string(),
            })
            .await
            .expect("plan_restore call should succeed");

        assert_eq!(result, "restored");
        let parsed: serde_json::Value =
            serde_json::from_str(&host.calls.lock().unwrap()[0].1).unwrap();
        assert_eq!(host.calls.lock().unwrap()[0].0, "plan_restore");
        assert_eq!(parsed["revision_id"], "rev-42");
    }

    #[tokio::test]
    async fn memory_add_routes_text_and_tags() {
        let host = Arc::new(RecordingHost::new("added"));
        let tool = MemoryAddTool::new(host.clone());

        let result = tool
            .call(MemoryAddArgs {
                text: "Prefers dumbbells over barbells for pressing.".to_string(),
                tags: Some(vec!["equipment".to_string(), "preference".to_string()]),
            })
            .await
            .expect("memory_add call should succeed");

        assert_eq!(result, "added");
        let calls = host.calls.lock().unwrap();
        assert_eq!(calls[0].0, "memory_add");
        let parsed: serde_json::Value = serde_json::from_str(&calls[0].1).unwrap();
        assert_eq!(parsed["text"], "Prefers dumbbells over barbells for pressing.");
        assert_eq!(parsed["tags"], json!(["equipment", "preference"]));
    }

    #[tokio::test]
    async fn memory_add_omits_tags_when_absent() {
        let host = Arc::new(RecordingHost::new("added"));
        let tool = MemoryAddTool::new(host.clone());

        tool.call(MemoryAddArgs {
            text: "Trains three days a week.".to_string(),
            tags: None,
        })
        .await
        .expect("memory_add call should succeed");

        let calls = host.calls.lock().unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&calls[0].1).unwrap();
        assert!(parsed.get("tags").is_none());
    }

    #[tokio::test]
    async fn memory_update_routes_expected_shape() {
        let host = Arc::new(RecordingHost::new("updated"));
        let tool = MemoryUpdateTool::new(host.clone());

        tool.call(MemoryUpdateArgs {
            id: "mem-1".to_string(),
            text: Some("Now trains four days a week.".to_string()),
            tags: None,
        })
        .await
        .expect("memory_update call should succeed");

        let calls = host.calls.lock().unwrap();
        assert_eq!(calls[0].0, "memory_update");
        let parsed: serde_json::Value = serde_json::from_str(&calls[0].1).unwrap();
        assert_eq!(parsed["id"], "mem-1");
        assert_eq!(parsed["text"], "Now trains four days a week.");
        assert!(parsed.get("tags").is_none());
    }

    #[tokio::test]
    async fn memory_query_routes_partial_args() {
        let host = Arc::new(RecordingHost::new("[]"));
        let tool = MemoryQueryTool::new(host.clone());

        tool.call(MemoryQueryArgs {
            query: Some("knee".to_string()),
            tags: None,
            limit: Some(5),
        })
        .await
        .expect("memory_query call should succeed");

        let calls = host.calls.lock().unwrap();
        assert_eq!(calls[0].0, "memory_query");
        let parsed: serde_json::Value = serde_json::from_str(&calls[0].1).unwrap();
        assert_eq!(parsed["query"], "knee");
        assert!(parsed.get("tags").is_none());
        assert_eq!(parsed["limit"], 5);
    }

    #[test]
    fn memory_query_args_deserialize_from_empty_object() {
        let args: MemoryQueryArgs =
            serde_json::from_str("{}").expect("memory_query args are all-optional");
        assert!(args.query.is_none());
        assert!(args.tags.is_none());
        assert!(args.limit.is_none());
    }

    #[tokio::test]
    async fn memory_remove_routes_id() {
        let host = Arc::new(RecordingHost::new("removed"));
        let tool = MemoryRemoveTool::new(host.clone());

        tool.call(MemoryRemoveArgs {
            id: "mem-7".to_string(),
        })
        .await
        .expect("memory_remove call should succeed");

        let calls = host.calls.lock().unwrap();
        assert_eq!(calls[0].0, "memory_remove");
        let parsed: serde_json::Value = serde_json::from_str(&calls[0].1).unwrap();
        assert_eq!(parsed["id"], "mem-7");
    }

    #[tokio::test]
    async fn session_apply_routes_operations() {
        let host = Arc::new(RecordingHost::new("applied"));
        let tool = SessionApplyTool::new(host.clone());

        let result = tool
            .call(SessionApplyArgs {
                operations: vec![
                    json!({"op": "adjustSet", "setID": "set-1", "weight": 225}),
                    json!({"op": "skipSet", "setID": "set-2"}),
                ],
            })
            .await
            .expect("session_apply call should succeed");

        assert_eq!(result, "applied");
        let calls = host.calls.lock().unwrap();
        assert_eq!(calls[0].0, "session_apply");
        let parsed: serde_json::Value = serde_json::from_str(&calls[0].1).unwrap();
        assert_eq!(parsed["operations"].as_array().unwrap().len(), 2);
        assert_eq!(parsed["operations"][0]["op"], "adjustSet");
        assert_eq!(parsed["operations"][1]["op"], "skipSet");
    }

    #[test]
    fn plan_apply_args_reject_missing_operations() {
        let bad: Result<PlanApplyArgs, _> = serde_json::from_str(r#"{"propose":true}"#);
        assert!(bad.is_err(), "operations is required and must be rejected");
    }

    #[test]
    fn session_apply_args_reject_missing_operations() {
        let bad: Result<SessionApplyArgs, _> = serde_json::from_str(r#"{}"#);
        assert!(bad.is_err(), "operations is required and must be rejected");
    }

    #[tokio::test]
    async fn escalate_to_reasoning_routes_optional_reason_and_returns_host_response() {
        let host = Arc::new(RecordingHost::new(
            "Switching to the reasoning model to work through this.",
        ));
        let tool = EscalateToReasoningTool::new(host.clone());

        let result = tool
            .call(EscalateToReasoningArgs {
                reason: Some("building a full plan from a vague description".to_string()),
            })
            .await
            .expect("escalate_to_reasoning call should succeed");

        assert_eq!(result, "Switching to the reasoning model to work through this.");
        let calls = host.calls.lock().unwrap();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].0, "escalate_to_reasoning");
        let parsed: serde_json::Value = serde_json::from_str(&calls[0].1).unwrap();
        assert_eq!(parsed["reason"], "building a full plan from a vague description");
    }

    #[tokio::test]
    async fn escalate_to_reasoning_omits_reason_when_absent() {
        let host = Arc::new(RecordingHost::new("ok"));
        let tool = EscalateToReasoningTool::new(host.clone());

        tool.call(EscalateToReasoningArgs { reason: None })
            .await
            .expect("escalate_to_reasoning call should succeed");

        let calls = host.calls.lock().unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&calls[0].1).unwrap();
        assert!(parsed.get("reason").is_none());
    }

    #[test]
    fn escalate_to_reasoning_args_deserialize_from_empty_object() {
        let args: EscalateToReasoningArgs =
            serde_json::from_str("{}").expect("escalate_to_reasoning args are all-optional");
        assert!(args.reason.is_none());
    }
}
