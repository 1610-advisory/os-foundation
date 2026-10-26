# Line-keeping rules merge. POSIX awk. No gawk features.
# Reads base, real, v1, map, and values. Writes the merged file.
# Company lines stay byte for byte. A base line with {{NAME}} is a pattern.

function trim(s) {
  gsub(/\r/, "", s)
  sub(/^[[:space:]]+/, "", s)
  sub(/[[:space:]]+$/, "", s)
  return s
}

function heading_level(line) {
  if (line ~ /^### /) return 3
  if (line ~ /^## /) return 2
  if (line ~ /^# /) return 1
  return 0
}

function is_h2(line) {
  return line ~ /^## [^#]/ || line ~ /^##$/
}

function h2_text(line) {
  return substr(line, 4)
}

function load_lines(path, arr,    n, line) {
  n = 0
  while ((getline line < path) > 0) {
    gsub(/\r/, "", line)
    n++
    arr[n] = line
  }
  close(path)
  return n
}

function split_sections(nlines, lines, sec_n, sec_name, sec_start, sec_end,    i, cur, sn) {
  sn = 0
  cur = 0
  for (i = 1; i <= nlines; i++) {
    if (is_h2(lines[i])) {
      if (cur > 0) sec_end[cur] = i - 1
      sn++
      sec_name[sn] = h2_text(lines[i])
      sec_start[sn] = i + 1
      cur = sn
    }
  }
  if (cur > 0) sec_end[cur] = nlines
  # Preamble is section 0 when the file has lines before the first ##.
  if (nlines > 0 && (sn == 0 || sec_start[1] > 2 || !is_h2(lines[1]))) {
    sec_n[0] = 1
    sec_name[0] = "_preamble"
    sec_start[0] = 1
    if (sn == 0) sec_end[0] = nlines
    else {
      i = 1
      while (i <= nlines && !is_h2(lines[i])) i++
      sec_end[0] = i - 1
    }
  }
  sec_n[1] = sn
  return sn
}

function has_section(sec_n, sec_name, name,    i, sn) {
  sn = sec_n[1]
  for (i = 1; i <= sn; i++) if (sec_name[i] == name) return i
  return 0
}

function literal_len(s,    t, n) {
  t = s
  n = 0
  while (match(t, /\{\{[A-Z][A-Z0-9_]*\}\}/)) {
    n += RSTART - 1
    t = substr(t, RSTART + RLENGTH)
  }
  return n + length(t)
}

function record_val(name, val) {
  if (name == "") return
  if (val ~ /\{\{/) return
  if (name in got && got[name] != "") return
  got[name] = val
}

# Returns 1 when real matches base. capture=1 stores placeholder values.
function pattern_match(base, real, capture,    rest, nparts, i, pos, lit, idx, val, name) {
  delete parts
  delete isph
  nparts = 0
  rest = base
  if (index(base, "{{") == 0) return base == real
  while (length(rest) > 0) {
    if (match(rest, /\{\{[A-Z][A-Z0-9_]*\}\}/)) {
      if (RSTART > 1) {
        nparts++
        parts[nparts] = substr(rest, 1, RSTART - 1)
        isph[nparts] = 0
      }
      nparts++
      parts[nparts] = substr(rest, RSTART + 2, RLENGTH - 4)
      isph[nparts] = 1
      rest = substr(rest, RSTART + RLENGTH)
    } else {
      nparts++
      parts[nparts] = rest
      isph[nparts] = 0
      rest = ""
    }
  }
  pos = 1
  for (i = 1; i <= nparts; i++) {
    if (!isph[i]) {
      lit = parts[i]
      if (substr(real, pos, length(lit)) != lit) return 0
      pos += length(lit)
      continue
    }
    name = parts[i]
    if (i == nparts) {
      val = substr(real, pos)
      pos = length(real) + 1
    } else if (isph[i + 1]) {
      val = ""
    } else {
      lit = parts[i + 1]
      idx = index(substr(real, pos), lit)
      if (idx == 0) return 0
      val = substr(real, pos, idx - 1)
      pos += length(val)
    }
    if (capture) record_val(name, val)
  }
  return pos == length(real) + 1
}

function replace_all(s, find, repl,    out, i) {
  if (find == "" || index(s, find) == 0) return s
  out = ""
  while ((i = index(s, find)) > 0) {
    out = out substr(s, 1, i - 1) repl
    s = substr(s, i + length(find))
  }
  return out s
}

function fill_line(line,    name, key) {
  for (name in got) {
    if (got[name] == "") continue
    key = "{{" name "}}"
    line = replace_all(line, key, got[name])
  }
  for (name in given) {
    if (name in got && got[name] != "") continue
    if (given[name] == "") continue
    key = "{{" name "}}"
    line = replace_all(line, key, given[name])
  }
  return line
}

function map_target(heading,    i, key, best, bestlen, rest) {
  best = ""
  bestlen = -1
  for (i = 1; i <= map_n; i++) {
    if (map_scope[i] != scope && map_scope[i] != "any") continue
    key = map_key[i]
    if (heading == key) {
      rest = ""
    } else if (index(heading, key) == 1) {
      rest = substr(heading, length(key) + 1)
      if (rest !~ /^ / && index(rest, " —") != 1) continue
    } else continue
    if (length(key) > bestlen) {
      bestlen = length(key)
      best = map_tgt[i]
    }
  }
  return best
}

function find_v1_heading(text,    i) {
  for (i = 1; i <= vn; i++) {
    if (v1[i] == text) return i
    if (text !~ /^#/ && (v1[i] == "## " text || v1[i] == "### " text)) return i
  }
  return 0
}

function block_end(start,    lvl, i, hl) {
  lvl = heading_level(v1[start])
  if (lvl == 0) lvl = 2
  for (i = start + 1; i <= vn; i++) {
    hl = heading_level(v1[i])
    if (hl > 0 && hl <= lvl) return i - 1
  }
  return vn
}

function add_insert(idx, depth, text) {
  ins_n[idx]++
  ins_depth[idx, ins_n[idx]] = depth
  ins_text[idx, ins_n[idx]] = text
}

function emit_inserts(idx,    i, j, d, tmpd, tmpt, n) {
  n = ins_n[idx]
  if (n == 0) return
  # Deeper headings first, then earlier groups. Stable for equal depth.
  for (i = 1; i <= n; i++) {
    for (j = i + 1; j <= n; j++) {
      if (ins_depth[idx, j] > ins_depth[idx, i]) {
        tmpd = ins_depth[idx, i]
        tmpt = ins_text[idx, i]
        ins_depth[idx, i] = ins_depth[idx, j]
        ins_text[idx, i] = ins_text[idx, j]
        ins_depth[idx, j] = tmpd
        ins_text[idx, j] = tmpt
      }
    }
  }
  for (i = 1; i <= n; i++) printf "%s", ins_text[idx, i] > out_path
}

BEGIN {
  if (base_path == "" || real_path == "") {
    print "rules-merge: missing file" > "/dev/stderr"
    exit 2
  }
  if (!score_only && (v1_path == "" || out_path == "")) {
    print "rules-merge: missing file" > "/dev/stderr"
    exit 2
  }
  bn = load_lines(base_path, bline)
  rn = load_lines(real_path, rline)
  split_sections(bn, bline, bsec_n, bsec_name, bsec_start, bsec_end)
  split_sections(rn, rline, rsec_n, rsec_name, rsec_start, rsec_end)

  if (values_path != "") {
    while ((getline line < values_path) > 0) {
      gsub(/\r/, "", line)
      if (line == "" || line ~ /^#/) continue
      eq = index(line, "=")
      if (eq < 2) continue
      given[substr(line, 1, eq - 1)] = substr(line, eq + 1)
    }
    close(values_path)
  }
  if (map_path != "") {
    while ((getline line < map_path) > 0) {
      gsub(/\r/, "", line)
      if (line == "" || line ~ /^#/) continue
      ntab = split(line, tab, "\t")
      if (ntab < 3) continue
      map_n++
      map_scope[map_n] = tab[1]
      map_key[map_n] = tab[2]
      map_tgt[map_n] = tab[3]
    }
    close(map_path)
  }

  company_n = 0
  spill_body = ""
  tail = ""

  # Section 0 is the preamble when present.
  sec_ids[1] = 0
  sec_count = 1
  for (s = 1; s <= rsec_n[1]; s++) {
    sec_count++
    sec_ids[sec_count] = s
  }

  for (si = 1; si <= sec_count; si++) {
    s = sec_ids[si]
    if (s == 0 && !rsec_n[0]) continue
    if (s > 0 && rsec_start[s] > rsec_end[s] && rsec_name[s] == "") continue
    name = (s == 0) ? "_preamble" : rsec_name[s]
    in_base = 0
    bsi = 0
    if (s == 0) {
      in_base = bsec_n[0] ? 1 : 0
      bsi = 0
    } else {
      bsi = has_section(bsec_n, bsec_name, name)
      in_base = bsi > 0
    }
    if (!in_base && s > 0) {
      # Company section, kept whole.
      block = "## " name "\n"
      for (i = rsec_start[s]; i <= rsec_end[s]; i++) {
        block = block rline[i] "\n"
        company_n++
      }
      # The heading itself is part of the kept section, not a company line.
      tail = tail block
      spill_body = spill_body block
      continue
    }

    # Match real lines to unused base lines.
    delete used
    bstart = (s == 0) ? bsec_start[0] : bsec_start[bsi]
    bend = (s == 0) ? bsec_end[0] : bsec_end[bsi]
    rstart = (s == 0) ? rsec_start[0] : rsec_start[s]
    rend = (s == 0) ? rsec_end[0] : rsec_end[s]
    block = ""
    if (rstart == 0 || rend == 0 || rstart > rend) continue
    for (i = rstart; i <= rend; i++) {
      best = 0
      best_score = -1
      exact = 0
      if (bstart > 0) {
        for (j = bstart; j <= bend; j++) {
          if (used[j]) continue
          if (rline[i] == bline[j]) {
            best = j
            exact = 1
            break
          }
        }
        if (!exact) {
          for (j = bstart; j <= bend; j++) {
            if (used[j]) continue
            if (index(bline[j], "{{") == 0) continue
            if (!pattern_match(bline[j], rline[i], 0)) continue
            score = literal_len(bline[j])
            # A pure placeholder should not swallow a later list line
            # when a plain line is still free. Prefer the closest index.
            if (score > best_score || (score == best_score && best == 0)) {
              best = j
              best_score = score
            }
          }
        }
      }
      if (best > 0) {
        used[best] = 1
        if (!exact) pattern_match(bline[best], rline[i], 1)
        matched++
      } else {
        block = block rline[i] "\n"
        company_n++
      }
    }
    if (block == "") continue
    target = ""
    depth = 2
    if (s == 0) {
      target = "_preamble"
      depth = 1
      spill_body = spill_body block
    } else {
      target = map_target(name)
      if (target == "") target = "## " name
      if (target ~ /^### /) depth = 3
      else if (target ~ /^## /) depth = 2
      else if (target ~ /^# /) depth = 1
      spill_body = spill_body "## " name "\n" block
    }
    # Stash. Applied after v1 is filled, because targets are v1 headings.
    hold_n++
    hold_target[hold_n] = target
    hold_depth[hold_n] = depth
    hold_block[hold_n] = block
    hold_name[hold_n] = name
  }

  if (score_only) {
    printf "company-lines=%d\n", company_n
    printf "matched=%d\n", matched + 0
    exit 0
  }

  # Fill v1.
  raw_n = load_lines(v1_path, raw)
  vn = raw_n
  for (i = 1; i <= vn; i++) v1[i] = fill_line(raw[i])

  for (h = 1; h <= hold_n; h++) {
    target = hold_target[h]
    if (target == "_preamble") {
      endi = 0
      for (i = 1; i <= vn; i++) {
        if (is_h2(v1[i])) { endi = i - 1; break }
      }
      if (endi < 0) endi = 0
      if (endi == 0 && vn > 0 && !is_h2(v1[1])) endi = vn
      add_insert(endi, hold_depth[h], hold_block[h])
      continue
    }
    start = find_v1_heading(target)
    if (start == 0) {
      # Keep the lines. Do not drop them.
      label = hold_name[h]
      if (label == "_preamble") tail = tail hold_block[h]
      else tail = tail "## " label "\n" hold_block[h]
      continue
    }
    endi = block_end(start)
    add_insert(endi, hold_depth[h], hold_block[h])
  }

  # Index 0 inserts belong before the first line (v1 starts with a heading).
  emit_inserts(0)
  for (i = 1; i <= vn; i++) {
    printf "%s\n", v1[i] > out_path
    emit_inserts(i)
  }
  if (tail != "") printf "%s", tail > out_path
  close(out_path)

  if (plain_path != "") {
    for (i = 1; i <= vn; i++) printf "%s\n", v1[i] > plain_path
    close(plain_path)
  }
  if (spill_path != "") {
    printf "%s", spill_body > spill_path
    if (tail != "") printf "%s", tail > spill_path
    close(spill_path)
  }
  printf "company-lines=%d\n", company_n
  printf "matched=%d\n", matched + 0
}
