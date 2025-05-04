use std::cell::RefCell;
use std::collections::HashMap;
use std::future::Future;
use std::sync::Arc;
use tokio::task_local;

#[derive(Default, Clone, Debug)]
pub struct RequestContext {
    pub req_id: Option<String>,
    pub session_id: Option<String>,
    pub additional: HashMap<String, String>,
}

impl RequestContext {
    pub fn new(req_id: Option<String>, session_id: Option<String>) -> Self {
        Self {
            req_id,
            session_id,
            additional: HashMap::new(),
        }
    }

    #[allow(dead_code)]
    pub fn insert(&mut self, key: &str, value: &str) {
        self.additional.insert(key.to_string(), value.to_string());
    }

    #[allow(dead_code)]
    pub fn get(&self, key: &str) -> Option<&String> {
        self.additional.get(key)
    }
}

task_local! {
    static CTX: RefCell<Arc<RequestContext>>;
}

pub async fn set_context_async<F, Fut>(ctx: RequestContext, fut: F) -> Fut::Output
where
    F: FnOnce() -> Fut,
    Fut: Future,
{
    let arc = Arc::new(ctx);
    CTX.scope(RefCell::new(arc), fut()).await
}

pub fn with_context<F, R>(f: F) -> R
where
    F: FnOnce(Arc<RequestContext>) -> R,
{
    CTX.with(|cell| f(cell.borrow().clone()))
}

#[allow(dead_code)]
pub fn try_with_context<F, R>(f: F) -> Option<R>
where
    F: FnOnce(Arc<RequestContext>) -> R,
{
    CTX.try_with(|cell| f(cell.borrow().clone())).ok()
}
