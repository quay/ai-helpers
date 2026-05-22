package main

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
)

type ExecResult struct {
	Stdout   string
	Stderr   string
	ExitCode int
}

func runCommand(ctx context.Context, dir string, name string, args ...string) (*ExecResult, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	if dir != "" {
		cmd.Dir = dir
	}

	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()

	result := &ExecResult{
		Stdout: stdout.String(),
		Stderr: stderr.String(),
	}

	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			result.ExitCode = exitErr.ExitCode()
			return result, fmt.Errorf("command %s exited with code %d: %s", name, result.ExitCode, stderr.String())
		}
		result.ExitCode = -1
		return result, fmt.Errorf("command %s failed: %w", name, err)
	}

	return result, nil
}
