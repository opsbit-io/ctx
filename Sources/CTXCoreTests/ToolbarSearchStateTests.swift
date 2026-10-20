import CTXCore
import Foundation

func runToolbarSearchStateTests() {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    var state = ToolbarSearchState()
    assert(!state.isExpanded, "toolbar search starts collapsed")

    state.activate(at: start)
    assert(state.isExpanded)
    assert(!state.collapseIfIdle(at: start.addingTimeInterval(1.19)))
    assert(state.collapseIfIdle(at: start.addingTimeInterval(1.2)))
    assert(!state.isExpanded, "empty search collapses after the idle delay")

    state.activate(at: start)
    state.focusChanged(true)
    assert(!state.collapseIfIdle(at: start.addingTimeInterval(10)))
    assert(state.isExpanded, "focused search must not collapse while the user is interacting with it")

    state.activate(at: start)
    state.setQuery("pods", at: start.addingTimeInterval(0.2))
    state.pointerExited()
    assert(state.isExpanded)
    assert(state.query == "pods", "pointer exit must not collapse or clear a nonempty search")
    assert(!state.collapseIfIdle(at: start.addingTimeInterval(10)))

    let submittedQuery = state.submit()
    assert(submittedQuery == "pods", "submission captures the query before collapse")
    assert(!state.isExpanded)
    assert(state.query.isEmpty)

    state.activate(at: start)
    state.setQuery("services", at: start)
    state.focusChanged(false)
    assert(!state.isExpanded)
    assert(state.query.isEmpty, "focus loss clears filtering state")

    state.activate(at: start)
    state.setQuery("nodes", at: start)
    state.escape()
    assert(!state.isExpanded)
    assert(state.query.isEmpty)

    state.activate(at: start)
    state.setQuery("deployments", at: start)
    state.resultSelected()
    assert(!state.isExpanded)
    assert(state.query.isEmpty)
}
