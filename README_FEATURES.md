# Tgz Splitter Enhanced Features

## New Features Added

### 1. Automatic Exclusions (Default)
Your archive files will now automatically be filtered to exclude:
- **SVG files** (vector graphics images)
- **JSON files** (JSON data files)
- **Large files** (over 10MB in size)

### 2. Markdown/Lean-Only Mode
You can now enable a mode that:
- Only shows Markdown (.md), Lean (.lean), and text files
- Excludes images, code files, and data files
- Focuses on documentation and text-based content

### 3. Pattern Analysis
The system now analyzes files for:
- Common text patterns (ngrams)
- Path patterns (directories, filenames)
- Common file types based on content
- File size and extension analysis

### 4. Smart File Categorization
Files are automatically categorized into:
- Lean (Lean proofs, documentation)
- Markdown (documentation, text files)
- Web (HTML, CSS, JavaScript)
- Graphics (images, SVGs)
- Source (source code files)
- Data (JSON, CSV, structured data)
- Binary (executables, libraries)
- Other (uncategorized)

### 5. Quick Selection Tools
You can now quickly select files by:
- Category (lean, web, docs, etc.)
- File type (text, binary, source, etc.)
- File size range
- Pattern matching (filename, path, content)
- Tag-based filtering

### 6. Pattern Analysis Tools
The system analyzes archive contents for:
- Common text patterns
- File path patterns
- Tag-based classification
- Content type detection

## How to Use the New Features

### 1. Default Behavior (Automatic Filtering)
All archive uploads automatically:
- Exclude SVG files
- Exclude JSON files
- Exclude files larger than 10MB
- Show only text-based files by default

### 2. Enable Markdown/Lean-Only Mode
To enable strict filtering:
1. Look for the "Markdown/Lean Only" option in the interface
2. Toggle it to enable strict filtering
3. Only Markdown, Lean, and text files will be shown
4. Other file types will be hidden from view

### 5. Pattern-Based Selection
You can now:
- Search for files by name patterns
- Search by content patterns (ngrams)
- Filter by file type categories
- Select files by directory structure
- Use tags to find related files

### 6. Pattern Analysis Tools
The system provides:
- Pattern extraction from file paths
- Ngram analysis from content
- Tag generation based on file properties
- Common pattern storage for quick access

## How to Access the New Features

1. **Upload an archive** as you normally would
2. **View the archive** in the archive viewer
3. **Use the filtering options**:
   - Toggle "Markdown/Lean Only" for strict filtering
   - Use the "Exclude" dropdown to customize exclusions
   - Use the search box to find files by pattern
   - Use category tabs to filter by file type

### Example Workflow

1. Upload a tgz file containing:
   - Report.md
   - Diagram.svg (excluded)
   - data.json (excluded)
   - proof.lean (included)
   - code.rs (included)
   - notes.txt (included)

2. The system will automatically:
   - Exclude diagram.svg and data.json
   - Show proof.lean, code.rs, and notes.txt
   - Categorize them appropriately

3. You can then:
   - Split the text files
   - Generate a summary
   - Extract specific files
   - Create a new archive with filtered content

## Configuration Options

You can customize the behavior via:
- Environment variables (e.g., MAX_FILE_SIZE)
- Configuration files (if available)
- UI controls in the web interface

The system is designed to be intuitive with sensible defaults while still offering customization options.