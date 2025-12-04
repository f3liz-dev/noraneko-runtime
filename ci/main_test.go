// SPDX-License-Identifier: MPL-2.0
package main

import (
	"testing"
)

func TestDefaultBuildConfig(t *testing.T) {
	cfg := DefaultBuildConfig()

	if cfg.Platform != PlatformLinux {
		t.Errorf("expected platform linux, got %s", cfg.Platform)
	}
	if cfg.Arch != ArchX86_64 {
		t.Errorf("expected arch x86_64, got %s", cfg.Arch)
	}
	if !cfg.Debug {
		t.Error("expected debug to be true by default")
	}
	if cfg.PGO {
		t.Error("expected PGO to be false by default")
	}
	if cfg.OmnijarCompress != "deflate" {
		t.Errorf("expected omnijar compress deflate, got %s", cfg.OmnijarCompress)
	}
}

func TestGetMozconfigPath(t *testing.T) {
	tests := []struct {
		name     string
		cfg      BuildConfig
		expected string
	}{
		{
			name: "linux x86_64",
			cfg: BuildConfig{
				Platform: PlatformLinux,
				Arch:     ArchX86_64,
			},
			expected: ".github/workflows/mozconfigs/linux-x86_64.mozconfig",
		},
		{
			name: "linux aarch64",
			cfg: BuildConfig{
				Platform: PlatformLinux,
				Arch:     ArchAarch64,
			},
			expected: ".github/workflows/mozconfigs/linux-aarch64.mozconfig",
		},
		{
			name: "windows x86_64",
			cfg: BuildConfig{
				Platform: PlatformWindows,
				Arch:     ArchX86_64,
			},
			expected: ".github/workflows/mozconfigs/windows-x86_64.mozconfig",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := getMozconfigPath(tt.cfg)
			if result != tt.expected {
				t.Errorf("expected %s, got %s", tt.expected, result)
			}
		})
	}
}

func TestGetObjectDir(t *testing.T) {
	tests := []struct {
		name     string
		cfg      BuildConfig
		expected string
	}{
		{
			name: "linux x86_64",
			cfg: BuildConfig{
				Platform: PlatformLinux,
				Arch:     ArchX86_64,
			},
			expected: "obj-x86_64-pc-linux-gnu",
		},
		{
			name: "linux aarch64",
			cfg: BuildConfig{
				Platform: PlatformLinux,
				Arch:     ArchAarch64,
			},
			expected: "obj-aarch64-unknown-linux-gnu",
		},
		{
			name: "windows x86_64",
			cfg: BuildConfig{
				Platform: PlatformWindows,
				Arch:     ArchX86_64,
			},
			expected: "obj-x86_64-pc-windows-msvc",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := getObjectDir(tt.cfg)
			if result != tt.expected {
				t.Errorf("expected %s, got %s", tt.expected, result)
			}
		})
	}
}

func TestGetArtifactExtension(t *testing.T) {
	tests := []struct {
		platform Platform
		expected string
	}{
		{PlatformLinux, "tar.xz"},
		{PlatformWindows, "zip"},
		{PlatformMac, "tar.xz"},
	}

	for _, tt := range tests {
		t.Run(string(tt.platform), func(t *testing.T) {
			result := getArtifactExtension(tt.platform)
			if result != tt.expected {
				t.Errorf("expected %s, got %s", tt.expected, result)
			}
		})
	}
}
