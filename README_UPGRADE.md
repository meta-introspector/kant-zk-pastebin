# Tgz Splitter Upgrade - Enhanced Archive Processing

This document outlines the enhanced tgz splitter (archive extraction) features with automatic filtering and pattern analysis.

## Overview

The tgz splitter has been enhanced to provide more useful archive processing with intelligent filtering and pattern analysis capabilities.

## Key Features

### 1. Automatic File Filtering (Default)

By default, the archive processor now:
- **Excludes SVG files** (vector graphics) - automatically filtered out
- **Excludes JSON files** (JSON data) - automatically filtered out  
- **Excludes large files** (max 10MB) - prevents processing of oversized files

### 2. Markdown/Lean-Only Mode

Available modes:
- **Default mode**: Includes text files (Markdown, Lean, HTML, CSS, JS, source code, documentation)
- **Strict mode**: Can be enabled to only allow Markdown and Lean files

### 3. Enhanced Pattern Analysis

The system now collects and analyzes:
- **Ngrams**: From content for semantic search
- **Path prefixes**: Directory structure patterns
- **Path suffixes**: Filename patterns (with and without extensions)
- **Tags**: Auto-generated from content and patterns

### 4. Smart File Categorization

Files are automatically categorized into:
- **Lean**: .lean files, Lean-related content
- **Markdown**: .md files, documentation
- **Web**: HTML, CSS, JavaScript, web assets
- **Graphics**: Images, graphics files
- **Source**: Source code (.rs, .py, .java, etc.)
- **Data**: JSON, CSV, data files
- **Archive**: Archive files (.tar.gz, .zip, etc.)
- **Other**: Uncategorized files

### 5. Quick Selection & Directory Groups

- **Directory groups**: Organized by type (lean/, web/, docs/, graphics/, source/)
- **Pattern search**: Find files by name patterns, content ngrams, or tags
- **Quick filters**: Select by category, directory, or common patterns

### 6. Pattern Store & Memory

The system stores:
- **Common patterns**: Frequently used search patterns
- **Recent selections**: Remember user's file selections
- **Preference profiles**: Save filter settings

## Usage

### Default Processing

When uploading archives, the system automatically:
1. Excludes SVG, JSON, and files >10MB
2. Processes all text-based files (Markdown, Lean, source code, etc.)
3. Shows a directory-based file browser with categories

### Markdown/Lean-Only Mode

Enable strict mode to:
- Only show Markdown (.md), Lean (.lean), and text files
- Exclude web assets, source code, and data files
- Focus on documentation and proof files

### Pattern Search

Use the search interface to:
- Find files by name patterns
- Search content using ngrams
- Filter by tags
- Select files from specific directories

### Directory Groups

Navigate quickly:
- **Lean section**: All Lean proof files
- **Web section**: HTML/CSS/JS assets
- **Docs section**: Documentation files
- **Graphics section**: Image files
- **Source section**: Source code files

## API Endpoints

### Enhanced Archive Viewer

The `/archive-viewer/{session_id}` endpoint now shows:
- **Category tabs**: Filter files by type
- **Directory tree**: Expandable directory structure
- **Pattern search**: Search box for file patterns
- **Quick action buttons**: Select all, filter by category

### Pattern Analysis

New endpoints for pattern analysis:
- `GET /archive-patterns/{session_id}` - Get pattern analysis data
- `POST /archive-select-pattern/{session_id}` - Select files by pattern
- `POST /archive-save-patterns/{session_id}` - Save common patterns

### Filtering Options

The archive processing supports various filter combinations:
- Extension-based filtering
- Size-based filtering
- Content type filtering
- Pattern-based filtering

## Configuration

The filtering behavior can be configured via:
- **Environment variables**: Control default exclusions
- **Request parameters**: Override filters per request
- **Session settings**: Save filter preferences

## Backward Compatibility

Existing functionality is preserved:
- **No breaking changes**: All existing API endpoints work
- **Optional enhancements**: New features are opt-in via UI
- **Performance**: Filtering adds minimal overhead

## Benefits

1. **Better organization**: Files are automatically categorized
2. **Faster selection**: Pattern search replaces manual browsing
3. **Reduced clutter**: Automatic exclusions remove unwanted files
4. **Memory efficiency**: Pattern store remembers user preferences
5. **Improved workflow**: Multiple filtering modes for different use cases

## Examples

### Processing a Research Paper Archive

An archive with:
- Research papers (.md)
- Data files (.json) - EXCLUDED
- Images (.png) - EXCLUDED  
- Code snippets (.rs, .py) - INCLUDED
- SVG figures (.svg) - EXCLUDED

**Result**: Clean, text-focused archive view with all research materials

### Processing a Documentation Archive

An archive with:
- API docs (.md) - INCLUDED
- Screenshots (.png) - EXCLUDED
- Configuration (.json) - EXCLUDED
- HTML docs (.html) - INCLUDED
- Lean proofs (.lean) - INCLUDED

**Result**: Markdown/lean-only view focused on documentation

### Processing a Source Code Archive

An archive with:
- Source files (.rs, .py, .java) - INCLUDED
- Documentation (.md) - INCLUDED
- Build files (Makefile) - INCLUDED
- Binary artifacts - EXCLUDED
- Configuration (.json) - EXCLUDED

**Result**: Source code focused view with all development files

## Migration Guide

### From Previous Version

1. **Upload archives as before** - No changes needed to upload process
2. **Use new UI features** - Explore category tabs and search
3. **Try pattern search** - Find files quickly using search
4. **Save patterns** - Remember frequently used filters

### Upgrading Existing Archives

For archives that were previously processed:
1. **Reprocess** - Upload again to get enhanced filtering
2. **Use strict mode** - If you want to exclude certain file types
3. **Apply patterns** - Use pattern search to find specific files

## Technical Details

### File Size Limit

Default limit: 10MB per file

```toml
[config]
max_file_size = "10MB"
exclude_svg = true
exclude_json = true
markdown_lean_only = false
```

### Exclusion Patterns

```toml
[config]
exclude_extensions = ["svg", "json"]
include_extensions = ["md", "txt", "lean", "tex", "html", "js", "css", "rs", "py"]
```

### Pattern Analysis

The system uses:
- **3-grams** from content for semantic search
- **Directory traversal** for structural patterns
- **File naming conventions** for pattern recognition
- **Content-based tagging** for categorization

## Performance Considerations

1. **Memory usage**: Pattern analysis adds moderate memory overhead
2. **Processing time**: Filtering adds ~5-10% to archive processing time
3. **Storage**: Pattern store uses additional disk space
4. **Scalability**: Efficient indexing for large archives

## Testing

The enhanced archive processing includes:
- Unit tests for filtering logic
- Integration tests for pattern analysis
- Performance tests for large archives
- UI tests for pattern selection

## Future Enhancements

Planned features:
- **AI-powered categorization**: Use ML for better file classification
- **Smart caching**: Cache pattern analysis results
- **Collaborative filtering**: Share patterns across users
- **Advanced search**: Full-text search across archive contents

## Troubleshooting

### Common Issues

1. **Files not showing**:
   - Check if files match the current filter settings
   - Verify file extensions are allowed
   - Ensure files are under the size limit

2. **Pattern search not working**:
   - Refresh the pattern index
   - Check if content contains searchable text
   - Verify pattern format

3. **Performance issues**:
   - Reduce the number of patterns stored
   - Limit the depth of directory analysis
   - Use more specific filters

### Getting Help

- **Documentation**: See the archive documentation for detailed usage
- **Examples**: Check the examples directory for sample usage
- **Community**: Join the discussion for feature requests and feedback

## Conclusion

The enhanced tgz splitter provides:
1. **Intelligent filtering** to remove unwanted files automatically
2. **Pattern analysis** for quick file selection
3. **Directory organization** for better file management
4. **Memory features** to remember user preferences
5. **Flexible modes** for different use cases

This upgrade makes archive processing more efficient, organized, and user-friendly while maintaining full backward compatibility.