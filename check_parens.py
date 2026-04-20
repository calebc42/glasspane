import sys

def check_parens(filename):
    with open(filename, encoding='utf-8') as f:
        lines = f.readlines()
    
    depth = 0
    in_string = False
    escaped = False
    
    for lineno, line in enumerate(lines, 1):
        for i, ch in enumerate(line):
            if escaped:
                escaped = False
                continue
            if ch == '\\':
                escaped = True
                continue
            if ch == '"' and not in_string:
                in_string = True
                continue
            if ch == '"' and in_string:
                in_string = False
                continue
            if in_string:
                continue
            if ch == ';':  # comment - skip rest of line
                break
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
                if depth < 0:
                    print(f"EXTRA CLOSE PAREN at line {lineno}, col {i+1}")
                    print(f"  {line.rstrip()}")
                    return
        
        # Print depth at end of each top-level form
        if depth == 0 and line.strip() and not line.strip().startswith(';'):
            pass  # balanced at this line
    
    if depth != 0:
        print(f"UNBALANCED: depth={depth} at end of file")
        # Find where it went wrong - track per-line
        depth = 0
        in_string = False
        escaped = False
        for lineno, line in enumerate(lines, 1):
            old_depth = depth
            for i, ch in enumerate(line):
                if escaped:
                    escaped = False
                    continue
                if ch == '\\':
                    escaped = True
                    continue
                if ch == '"' and not in_string:
                    in_string = True
                    continue
                if ch == '"' and in_string:
                    in_string = False
                    continue
                if in_string:
                    continue
                if ch == ';':
                    break
                if ch == '(':
                    depth += 1
                elif ch == ')':
                    depth -= 1
            if depth != old_depth:
                delta = depth - old_depth
                if abs(delta) > 2 or depth < 2:
                    print(f"  Line {lineno}: depth {old_depth} -> {depth} (delta {delta:+d}): {line.rstrip()[:80]}")
    else:
        print("BALANCED - parens are OK")

check_parens(sys.argv[1])
