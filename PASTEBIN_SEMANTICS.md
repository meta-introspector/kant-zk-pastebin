# Standard Pastebin Semantics - Requirements

## Core Features (Must Have)

### 1. Create Paste
- [ ] Large textarea (main focus)
- [ ] Optional title
- [ ] Optional syntax highlighting
- [ ] Optional expiration
- [ ] Submit button → redirect to paste URL

### 2. View Paste
- [ ] Raw text view
- [ ] Copy button
- [ ] Download button
- [ ] Reply/Fork button
- [ ] Share URL

### 3. Browse/List
- [ ] Recent pastes
- [ ] Search
- [ ] Filter by date/size

### 4. URLs
- [ ] `/` - Create new paste
- [ ] `/paste/{id}` - View paste
- [ ] `/raw/{id}` - Raw text
- [ ] `/browse` - List pastes

## Current Issues

1. **Reply button broken** - Uses title instead of full ID
2. **No raw view** - Can't get plain text
3. **Complex UI** - Too many features upfront
4. **JS required** - Should work without JS

## Fix Priority

1. Fix reply_to URL (use full ID)
2. Add /raw/{id} endpoint
3. Simplify home page (focus on textarea)
4. Make reply button a plain link
5. Test complete workflow
