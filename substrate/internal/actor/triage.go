package actor

import "strings"

type TriageResult struct {
	Ready    bool
	Refuse   bool
	Blockers []string
}

func triageTicket(state *ActorState) TriageResult {
	if state.JIRA == nil {
		return TriageResult{Blockers: []string{"missing JIRA context"}}
	}

	if state.JIRA.EmbargoStatus == "True" {
		return TriageResult{Refuse: true}
	}

	var blockers []string

	if strings.TrimSpace(state.JIRA.Description) == "" {
		blockers = append(blockers, "missing description")
	}

	if state.JIRA.Type == "Bug" && !hasReproSection(state.JIRA.Description) {
		blockers = append(blockers, "missing reproduction steps")
	}

	if state.JIRA.Type != "Bug" && strings.TrimSpace(state.JIRA.AcceptanceCriteria) == "" {
		blockers = append(blockers, "missing acceptance criteria")
	}

	return TriageResult{
		Ready:    len(blockers) == 0,
		Blockers: blockers,
	}
}

func hasReproSection(desc string) bool {
	lower := strings.ToLower(desc)
	return strings.Contains(lower, "steps to reproduce") ||
		strings.Contains(lower, "reproduction") ||
		strings.Contains(lower, "how to reproduce")
}
