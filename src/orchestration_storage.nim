import std/[os, times]

type
  OrchestrationPaths* = object
    root*: string
    artifacts*: string
    backups*: string

proc orchestration_paths*(cwd: string): OrchestrationPaths =
  let canonical_cwd = expandFilename(cwd)
  let root = joinPath(canonical_cwd, "orchestration")
  result = OrchestrationPaths(
    root: root,
    artifacts: joinPath(root, "artifacts"),
    backups: joinPath(root, "backups"))

proc path_exists*(path: string): bool =
  dirExists(path) or fileExists(path)

proc next_backup_path(backups: string): string =
  let base_path = joinPath(backups, $int64(epochTime()))
  result = base_path
  var suffix = 0
  while result.path_exists:
    inc suffix
    result = base_path & "-" & $suffix

proc contains_work(path: string): bool =
  for kind, child_path in walkDir(path):
    if kind == pcDir:
      if child_path.contains_work:
        return true
    else:
      return true
  false

proc initialize_orchestration_storage*(cwd: string): OrchestrationPaths =
  result = orchestration_paths(cwd)
  if fileExists(result.root):
    raise newException(ValueError,
      "orchestration path is not a directory: " & result.root)

  createDir(result.root)
  createDir(result.backups)

  var active_entries: seq[(PathComponent, string)] = @[]
  for kind, path in walkDir(result.root):
    if lastPathPart(path) != "backups" and
        (kind != pcDir or path.contains_work):
      active_entries.add((kind, path))

  if active_entries.len > 0:
    let backup_path = next_backup_path(result.backups)
    createDir(backup_path)
    for entry in active_entries:
      let kind = entry[0]
      let path = entry[1]
      let destination = joinPath(backup_path, lastPathPart(path))
      if kind == pcDir:
        moveDir(path, destination)
      else:
        moveFile(path, destination)

  createDir(result.artifacts)
