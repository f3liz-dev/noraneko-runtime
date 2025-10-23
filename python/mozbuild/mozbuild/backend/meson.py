# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

"""Backend that generates meson.build files from moz.build files."""

import os
from collections import defaultdict

import mozpack.path as mozpath

from mozbuild.backend.base import PartialBackend
from mozbuild.frontend.data import (
    BaseLibrary,
    BaseProgram,
    BaseRustLibrary,
    ComputedFlags,
    Defines,
    DirectoryTraversal,
    Exports,
    GeneratedFile,
    HostDefines,
    HostLibrary,
    HostProgram,
    HostRustLibrary,
    HostRustProgram,
    HostSimpleProgram,
    HostSources,
    LocalInclude,
    PerSourceFlag,
    Program,
    RustLibrary,
    RustProgram,
    SharedLibrary,
    SimpleProgram,
    Sources,
    StaticLibrary,
    VariablePassthru,
)
from mozbuild.util import FileAvoidWrite


class MesonBackend(PartialBackend):
    """Backend that generates meson.build files.
    
    This backend converts TreeMetadata objects from moz.build files
    into meson.build files that can be used with the Meson build system.
    """

    def _init(self):
        """Initialize the backend state."""
        # Track meson.build content for each directory
        self._meson_files = defaultdict(list)
        
        # Track sources for each target
        self._target_sources = defaultdict(list)
        self._target_host_sources = defaultdict(list)
        
        # Track programs and libraries
        self._programs = {}
        self._libraries = {}
        
        # Track defines
        self._defines = defaultdict(dict)
        self._host_defines = defaultdict(dict)
        
        # Track include directories
        self._local_includes = defaultdict(list)
        
        # Track generated files
        self._generated_files = defaultdict(list)
        
        # Track exports
        self._exports = defaultdict(list)
        
        # Track subdirectories
        self._subdirs = defaultdict(list)
        
        # Track compile flags
        self._compile_flags = defaultdict(dict)
        
        # Track per-source flags
        self._per_source_flags = defaultdict(dict)
        
        # Track variable passthrough
        self._variable_passthru = defaultdict(dict)
        
        # Track the current directory being processed
        self._current_dir = None

    def consume_object(self, obj):
        """Process a single TreeMetadata object.
        
        Args:
            obj: A TreeMetadata object from the frontend
            
        Returns:
            True if the object was handled, False otherwise
        """
        if isinstance(obj, (Sources, HostSources)):
            return self._handle_sources(obj)
        elif isinstance(obj, (Program, HostProgram, SimpleProgram, HostSimpleProgram)):
            return self._handle_program(obj)
        elif isinstance(obj, (RustProgram, HostRustProgram)):
            return self._handle_rust_program(obj)
        elif isinstance(obj, (StaticLibrary, SharedLibrary, HostLibrary)):
            return self._handle_library(obj)
        elif isinstance(obj, (RustLibrary, HostRustLibrary)):
            return self._handle_rust_library(obj)
        elif isinstance(obj, (Defines, HostDefines)):
            return self._handle_defines(obj)
        elif isinstance(obj, LocalInclude):
            return self._handle_local_include(obj)
        elif isinstance(obj, GeneratedFile):
            return self._handle_generated_file(obj)
        elif isinstance(obj, Exports):
            return self._handle_exports(obj)
        elif isinstance(obj, DirectoryTraversal):
            return self._handle_directory_traversal(obj)
        elif isinstance(obj, ComputedFlags):
            return self._handle_computed_flags(obj)
        elif isinstance(obj, PerSourceFlag):
            return self._handle_per_source_flag(obj)
        elif isinstance(obj, VariablePassthru):
            return self._handle_variable_passthru(obj)
        
        # We don't handle this object type
        return False

    def _handle_sources(self, obj):
        """Handle Sources and HostSources objects."""
        # Group sources by directory
        objdir = obj.objdir
        
        if isinstance(obj, HostSources):
            for source in obj.files:
                self._target_host_sources[objdir].append(str(source))
        else:
            for source in obj.files:
                self._target_sources[objdir].append(str(source))
        
        return True

    def _handle_program(self, obj):
        """Handle Program and HostProgram objects."""
        self._programs[obj.objdir] = {
            'name': obj.program,
            'is_host': isinstance(obj, HostProgram),
            'objdir': obj.objdir,
            'srcdir': obj.srcdir,
        }
        return True

    def _handle_library(self, obj):
        """Handle library objects (static, shared, host)."""
        lib_name = getattr(obj, 'basename', None) or getattr(obj, 'lib_name', 'unknown')
        
        self._libraries[obj.objdir] = {
            'name': lib_name,
            'is_static': isinstance(obj, StaticLibrary),
            'is_shared': isinstance(obj, SharedLibrary),
            'is_host': isinstance(obj, HostLibrary),
            'objdir': obj.objdir,
            'srcdir': obj.srcdir,
        }
        return True

    def _handle_rust_program(self, obj):
        """Handle Rust program objects."""
        self._programs[obj.objdir] = {
            'name': obj.name,
            'is_host': isinstance(obj, HostRustProgram),
            'is_rust': True,
            'objdir': obj.objdir,
            'srcdir': obj.srcdir,
        }
        return True

    def _handle_rust_library(self, obj):
        """Handle Rust library objects."""
        lib_name = getattr(obj, 'basename', None) or getattr(obj, 'lib_name', 'unknown')
        
        self._libraries[obj.objdir] = {
            'name': lib_name,
            'is_static': True,  # Rust libraries are typically static
            'is_shared': False,
            'is_host': isinstance(obj, HostRustLibrary),
            'is_rust': True,
            'objdir': obj.objdir,
            'srcdir': obj.srcdir,
        }
        return True

    def _handle_defines(self, obj):
        """Handle Defines and HostDefines objects."""
        objdir = obj.objdir
        
        defines_dict = self._host_defines if isinstance(obj, HostDefines) else self._defines
        
        for key, value in obj.defines.items():
            if value is True:
                defines_dict[objdir][key] = None
            else:
                defines_dict[objdir][key] = value
        
        return True

    def _handle_local_include(self, obj):
        """Handle LocalInclude objects."""
        self._local_includes[obj.objdir].append(obj.path)
        return True

    def _handle_generated_file(self, obj):
        """Handle GeneratedFile objects."""
        self._generated_files[obj.objdir].append({
            'outputs': obj.outputs,
            'script': getattr(obj, 'script', None),
            'inputs': getattr(obj, 'inputs', []),
        })
        return True

    def _handle_exports(self, obj):
        """Handle Exports objects."""
        for path in obj.files:
            self._exports[obj.objdir].append(str(path))
        return True

    def _handle_directory_traversal(self, obj):
        """Handle DirectoryTraversal objects."""
        for subdir in obj.dirs:
            self._subdirs[obj.objdir].append(subdir)
        return True

    def _handle_computed_flags(self, obj):
        """Handle ComputedFlags objects."""
        objdir = obj.objdir
        
        if hasattr(obj, 'flags') and obj.flags:
            for flag_type, flags in obj.flags.items():
                if flag_type not in self._compile_flags[objdir]:
                    self._compile_flags[objdir][flag_type] = []
                self._compile_flags[objdir][flag_type].extend(flags)
        
        return True

    def _handle_per_source_flag(self, obj):
        """Handle PerSourceFlag objects."""
        objdir = obj.objdir
        source = obj.file_name
        
        if source not in self._per_source_flags[objdir]:
            self._per_source_flags[objdir][source] = []
        
        self._per_source_flags[objdir][source].extend(obj.flags)
        return True

    def _handle_variable_passthru(self, obj):
        """Handle VariablePassthru objects."""
        objdir = obj.objdir
        
        for key, value in obj.variables.items():
            self._variable_passthru[objdir][key] = value
        
        return True

    def consume_finished(self):
        """Called when all objects have been consumed.
        
        This generates the actual meson.build files.
        """
        # Generate meson.build files for each directory that has build targets
        all_dirs = set()
        all_dirs.update(self._programs.keys())
        all_dirs.update(self._libraries.keys())
        all_dirs.update(self._target_sources.keys())
        all_dirs.update(self._target_host_sources.keys())
        all_dirs.update(self._defines.keys())
        all_dirs.update(self._host_defines.keys())
        all_dirs.update(self._local_includes.keys())
        all_dirs.update(self._generated_files.keys())
        all_dirs.update(self._exports.keys())
        all_dirs.update(self._subdirs.keys())
        all_dirs.update(self._compile_flags.keys())
        
        for objdir in all_dirs:
            self._generate_meson_build(objdir)
        
        # Generate the top-level meson.build file
        self._generate_top_level_meson_build()

    def _generate_meson_build(self, objdir):
        """Generate a meson.build file for a specific directory."""
        content_lines = []
        content_lines.append("# Generated by mozbuild's Meson backend")
        content_lines.append("")
        
        # Add defines
        defines = self._defines.get(objdir, {})
        host_defines = self._host_defines.get(objdir, {})
        
        if defines or host_defines:
            content_lines.append("# Defines")
            all_defines = {}
            all_defines.update(defines)
            all_defines.update(host_defines)
            
            for key, value in all_defines.items():
                if value is None:
                    content_lines.append(f"add_project_arguments('-D{key}', language: ['c', 'cpp'])")
                else:
                    content_lines.append(f"add_project_arguments('-D{key}={value}', language: ['c', 'cpp'])")
            content_lines.append("")
        
        # Add include directories
        local_includes = self._local_includes.get(objdir, [])
        if local_includes:
            content_lines.append("# Include directories")
            content_lines.append("inc_dirs = include_directories([")
            for inc in local_includes:
                content_lines.append(f"  '{inc}',")
            content_lines.append("])")
            content_lines.append("")
        
        # Add generated files
        generated_files = self._generated_files.get(objdir, [])
        if generated_files:
            content_lines.append("# Generated files")
            for gen in generated_files:
                if gen['script']:
                    content_lines.append(f"# Generated: {', '.join(gen['outputs'])}")
                    content_lines.append(f"# Script: {gen['script']}")
                content_lines.append("")
        
        # Add sources if any
        sources = self._target_sources.get(objdir, [])
        host_sources = self._target_host_sources.get(objdir, [])
        
        # Build compile flags
        compile_flags = []
        flags_dict = self._compile_flags.get(objdir, {})
        for flag_type, flags in flags_dict.items():
            compile_flags.extend(flags)
        
        # Add program if any
        program = self._programs.get(objdir)
        if program:
            src_list = sources or host_sources
            if src_list:
                content_lines.append(f"# Program: {program['name']}")
                content_lines.append("sources = [")
                for src in src_list:
                    content_lines.append(f"  '{src}',")
                content_lines.append("]")
                content_lines.append("")
                
                exe_name = program['name']
                exe_kwargs = []
                
                if local_includes:
                    exe_kwargs.append("include_directories: inc_dirs")
                
                if compile_flags:
                    flags_str = ", ".join(f"'{f}'" for f in compile_flags)
                    exe_kwargs.append(f"cpp_args: [{flags_str}]")
                
                kwargs_str = ", ".join(exe_kwargs)
                
                if program.get('is_rust'):
                    content_lines.append(f"# Rust program: {exe_name}")
                    content_lines.append(f"# Note: Meson Rust support may be limited")
                elif program.get('is_host'):
                    if kwargs_str:
                        content_lines.append(f"executable('{exe_name}', sources, native: true, {kwargs_str})")
                    else:
                        content_lines.append(f"executable('{exe_name}', sources, native: true)")
                else:
                    if kwargs_str:
                        content_lines.append(f"executable('{exe_name}', sources, {kwargs_str})")
                    else:
                        content_lines.append(f"executable('{exe_name}', sources)")
                content_lines.append("")
        
        # Add library if any
        library = self._libraries.get(objdir)
        if library:
            src_list = sources or host_sources
            if src_list:
                content_lines.append(f"# Library: {library['name']}")
                content_lines.append("sources = [")
                for src in src_list:
                    content_lines.append(f"  '{src}',")
                content_lines.append("]")
                content_lines.append("")
                
                lib_name = library['name']
                lib_kwargs = []
                
                if local_includes:
                    lib_kwargs.append("include_directories: inc_dirs")
                
                if compile_flags:
                    flags_str = ", ".join(f"'{f}'" for f in compile_flags)
                    lib_kwargs.append(f"cpp_args: [{flags_str}]")
                
                kwargs_str = ", ".join(lib_kwargs)
                
                if library.get('is_rust'):
                    content_lines.append(f"# Rust library: {lib_name}")
                    content_lines.append(f"# Note: Meson Rust support may be limited")
                elif library['is_shared']:
                    if kwargs_str:
                        content_lines.append(f"shared_library('{lib_name}', sources, {kwargs_str})")
                    else:
                        content_lines.append(f"shared_library('{lib_name}', sources)")
                elif library['is_static']:
                    if kwargs_str:
                        content_lines.append(f"static_library('{lib_name}', sources, {kwargs_str})")
                    else:
                        content_lines.append(f"static_library('{lib_name}', sources)")
                else:
                    if kwargs_str:
                        content_lines.append(f"library('{lib_name}', sources, {kwargs_str})")
                    else:
                        content_lines.append(f"library('{lib_name}', sources)")
                content_lines.append("")
        
        # Add subdirectories
        subdirs = self._subdirs.get(objdir, [])
        if subdirs:
            content_lines.append("# Subdirectories")
            for subdir in subdirs:
                content_lines.append(f"subdir('{subdir}')")
            content_lines.append("")
        
        # Only write the file if there's actual content
        if len(content_lines) > 2:  # More than just the header
            # Write to objdir
            meson_build_path = mozpath.join(objdir, "meson.build")
            
            with self._write_file(meson_build_path) as fh:
                fh.write("\n".join(content_lines))

    def _generate_top_level_meson_build(self):
        """Generate the top-level meson.build file."""
        content_lines = []
        content_lines.append("# Top-level meson.build generated by mozbuild")
        content_lines.append("")
        content_lines.append("project('mozilla', 'c', 'cpp',")
        content_lines.append("  version: '1.0',")
        content_lines.append("  default_options: ['warning_level=3'])")
        content_lines.append("")
        
        # Find all subdirectories that have meson.build files
        subdirs = set()
        for objdir in set(list(self._programs.keys()) + list(self._libraries.keys())):
            # Get relative path from topobjdir
            reldir = mozpath.relpath(objdir, self.environment.topobjdir)
            if reldir and reldir != '.':
                subdirs.add(reldir)
        
        if subdirs:
            content_lines.append("# Subdirectories")
            for subdir in sorted(subdirs):
                content_lines.append(f"subdir('{subdir}')")
            content_lines.append("")
        
        top_meson_build = mozpath.join(self.environment.topobjdir, "meson.build")
        
        with self._write_file(top_meson_build) as fh:
            fh.write("\n".join(content_lines))
