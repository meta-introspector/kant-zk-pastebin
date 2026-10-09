with open('src/handlers.rs', 'r') as f:
    lines = f.readlines()

new_lines = []
for i, line in enumerate(lines):
    if 'let pattern_store = PatternStore::from_archive_entries' in line:
        j = i + 1
        while j < len(lines) and 'ARCHIVE_STORE.lock().unwrap().insert' not in lines[j]:
            j += 1
        insert_line = lines[j]
        new_insert = insert_line.replace(
            '.insert(session_id.clone(), (result, pattern_store));',
            '.insert(session_id.clone(), result);'
        )
        lines[j] = new_insert
        continue
    new_lines.append(line)

with open('src/handlers.rs', 'w') as f:
    f.writelines(new_lines)

print("Done fixing ARCHIVE_STORE insert")
