# .changefile Migration Analysis

## Overview
This document identifies all code locations that need modification to support the new `.changefile` approach instead of `.lockfile`. The `.changefile` will contain timestamp and path information, while `.lockfile` will be created with `/dev/null` contents.

---

## 1. FCStdFileTool.py Changes

### 1.1 `create_lockfile()` Function (Lines 455-470)
**Current Implementation:**
- Creates `.lockfile` with timestamp and FCStd file path
- File: `FreeCAD_Automation/FCStdFileTool.py:455-470`

**Required Changes:**
1. Create `.changefile` with timestamp and path (current `.lockfile` content)
2. Create `.lockfile` with `/dev/null` content
3. Consider renaming function to `create_lock_and_change_files()` for clarity

**Impact:** This is the PRIMARY change that creates both files during export.

---

### 1.2 `--lockfile` Flag and Related Code (Lines 5, 31-32, 115, 492-500)
**Current Implementation:**
- CLI flag `--lockfile` returns path to `.lockfile`
- Used by shell scripts to get lockfile path

**Required Changes:**
1. Add new flag `--changefile` to return `.changefile` path
2. Keep `--lockfile` flag for backward compatibility (returns `.lockfile` path)
3. Update help message to document both flags
4. Add logic in main() to handle `--changefile` flag

**Files to modify:**
- `FreeCAD_Automation/FCStdFileTool.py:5` (add CHANGEFILE_FLAG constant)
- `FreeCAD_Automation/FCStdFileTool.py:31-32` (update help message)
- `FreeCAD_Automation/FCStdFileTool.py:115` (add argparse argument)
- `FreeCAD_Automation/FCStdFileTool.py:492-500` (add changefile handling)

---

### 1.3 Export Logic - Lockfile Deletion (Lines 514-517)
**Current Implementation:**
- Deletes old `.lockfile` before export

**Required Changes:**
1. Also delete old `.changefile` if it exists
2. Handle permissions for both files

**Code Location:** `FreeCAD_Automation/FCStdFileTool.py:514-517`

---

## 2. Shell Script Changes

### 2.1 utils.sh - Core Utility Functions

#### 2.1.1 `get_FCStd_file_from_lockfile()` Function (Lines 227-260)
**Current Implementation:**
- Reads `.lockfile` to extract FCStd file path
- Parses `FCStd_file_relpath=` line

**Required Changes:**
1. Rename to `get_FCStd_file_from_changefile()`
2. Update to read from `.changefile` instead of `.lockfile`
3. Keep same parsing logic (since `.changefile` will have same format)
4. **CRITICAL:** This function is called by MANY other scripts

**Impact:** HIGH - This is a core utility function used throughout the codebase.

---

#### 2.1.2 `get_FCStd_dir()` Function (Lines 209-225)
**Current Implementation:**
- Gets lockfile path, then returns its directory

**Required Changes:**
1. Update to use `--changefile` flag instead of `--lockfile`
2. Get changefile path and return its directory

**Code Location:** `FreeCAD_Automation/utils.sh:209-225`

---

#### 2.1.3 `FCStd_file_has_valid_lock()` Function (Lines 147-207)
**Current Implementation:**
- Gets lockfile path to check lock status
- Checks if lockfile is tracked in git

**Required Changes:**
1. Update to use `--changefile` flag to get directory path
2. Still check `.lockfile` for git-lfs lock status (since that's what's locked)
3. Check if `.changefile` is tracked in git (not `.lockfile`)

**Code Location:** `FreeCAD_Automation/utils.sh:147-207`

---

### 2.2 lock.sh (Lines 66-69)
**Current Implementation:**
- Gets lockfile path using `--lockfile` flag
- Locks the lockfile with git-lfs

**Required Changes:**
1. Keep getting lockfile path (still locking `.lockfile`)
2. No changes needed - still locking `.lockfile` via git-lfs

**Code Location:** `FreeCAD_Automation/lock.sh:66-69`

**Impact:** NONE - Still locking `.lockfile`, just its contents change.

---

### 2.3 unlock.sh (Lines 68-73)
**Current Implementation:**
- Gets lockfile path and unlocks it
- Gets FCStd directory from lockfile path

**Required Changes:**
1. Keep getting lockfile path (still unlocking `.lockfile`)
2. No changes needed - still unlocking `.lockfile` via git-lfs

**Code Location:** `FreeCAD_Automation/unlock.sh:68-73`

**Impact:** NONE - Still unlocking `.lockfile`.

---

### 2.4 init-repo.sh (Lines 190-199)
**Current Implementation:**
- Configures git-lfs to track `.lockfile` as lockable
- Sets up locksverify

**Required Changes:**
1. Keep `.lockfile` tracking (still locking this file)
2. Add `.changefile` to git tracking (NOT as lockable, just regular tracking)
3. Consider adding `.changefile` to .gitattributes

**Code Location:** `FreeCAD_Automation/init-repo.sh:190-199`

---

### 2.5 Git Hooks - Pattern Matching

All hooks that search for changed `.lockfile` files need updates:

#### 2.5.1 pre-commit (Lines 24-39)
**Current Implementation:**
- Gets staged `.lockfile` files
- Checks user has locks for them

**Required Changes:**
1. Change grep pattern from `'\.lockfile$'` to `'\.changefile$'`
2. Update variable names: `STAGED_LOCKFILES` → `STAGED_CHANGEFILES`
3. Still check locks against `.lockfile` path (derive from `.changefile` path)

**Code Location:** `FreeCAD_Automation/hooks/pre-commit:24-39`

---

#### 2.5.2 pre-push (Lines 59-74)
**Current Implementation:**
- Gets changed `.lockfile` files between commits
- Verifies user has locks

**Required Changes:**
1. Change grep pattern from `'\.lockfile$'` to `'\.changefile$'`
2. Update variable names: `changed_lockfiles` → `changed_changefiles`
3. Derive `.lockfile` path from `.changefile` path for lock checking

**Code Location:** `FreeCAD_Automation/hooks/pre-push:59-74`

---

#### 2.5.3 post-checkout (Lines 54-87)
**Current Implementation:**
- Gets changed `.lockfile` files
- Imports FCStd files
- Sets readonly/writable based on locks

**Required Changes:**
1. Change grep pattern from `'\.lockfile$'` to `'\.changefile$'`
2. Update variable names: `changed_lockfiles` → `changed_changefiles`
3. Update function call: `get_FCStd_file_from_lockfile` → `get_FCStd_file_from_changefile`
4. Derive `.lockfile` path for lock checking

**Code Location:** `FreeCAD_Automation/hooks/post-checkout:54-87`

---

#### 2.5.4 post-commit (Lines 35-47)
**Current Implementation:**
- Gets committed `.lockfile` files
- Sets file permissions based on locks

**Required Changes:**
1. Change grep pattern from `'\.lockfile$'` to `'\.changefile$'`
2. Update variable names
3. Update function call to `get_FCStd_file_from_changefile`
4. Derive `.lockfile` path for lock checking

**Code Location:** `FreeCAD_Automation/hooks/post-commit:35-47`

---

#### 2.5.5 post-merge (Lines 51-84)
**Current Implementation:**
- Gets changed `.lockfile` files
- Imports FCStd files
- Sets permissions

**Required Changes:**
1. Change grep pattern from `'\.lockfile$'` to `'\.changefile$'`
2. Update variable names: `changed_lockfiles` → `changed_changefiles`
3. Update function call to `get_FCStd_file_from_changefile`
4. Derive `.lockfile` path for lock checking

**Code Location:** `FreeCAD_Automation/hooks/post-merge:51-84`

---

#### 2.5.6 post-rewrite (Lines 45-78)
**Current Implementation:**
- Gets changed `.lockfile` files
- Imports FCStd files
- Sets permissions

**Required Changes:**
1. Change grep pattern from `'\.lockfile$'` to `'\.changefile$'`
2. Update variable names: `changed_lockfiles` → `changed_changefiles`
3. Update function call to `get_FCStd_file_from_changefile`
4. Derive `.lockfile` path for lock checking

**Code Location:** `FreeCAD_Automation/hooks/post-rewrite:45-78`

---

### 2.6 FCStdStash.sh (Lines 53, 75, 96, 110)
**Current Implementation:**
- Searches for `.lockfile` files in stash and working directory
- Checks locks and imports files

**Required Changes:**
1. Change all grep patterns from `'\.lockfile$'` to `'\.changefile$'`
2. Update variable names: `*_LOCKFILES` → `*_CHANGEFILES`
3. Update function call to `get_FCStd_file_from_changefile`
4. Derive `.lockfile` path for lock checking

**Code Locations:**
- `FreeCAD_Automation/FCStdStash.sh:53` (stashed files)
- `FreeCAD_Automation/FCStdStash.sh:75` (working dir)
- `FreeCAD_Automation/FCStdStash.sh:96` (before stash)
- `FreeCAD_Automation/FCStdStash.sh:110` (after stash)

---

### 2.7 FCStdReset.sh (Lines 28, 76, 91)
**Current Implementation:**
- Tracks `.lockfile` changes before/after reset
- Imports affected FCStd files

**Required Changes:**
1. Change all grep patterns from `'\.lockfile$'` to `'\.changefile$'`
2. Update variable names: `*_LOCKFILES` → `*_CHANGEFILES`
3. Update function call to `get_FCStd_file_from_changefile` (line 151)
4. Derive `.lockfile` path for lock checking

**Code Locations:**
- `FreeCAD_Automation/FCStdReset.sh:28` (before reset)
- `FreeCAD_Automation/FCStdReset.sh:76` (changed between commits)
- `FreeCAD_Automation/FCStdReset.sh:91` (after reset)
- `FreeCAD_Automation/FCStdReset.sh:99` (deconflict logic)
- `FreeCAD_Automation/FCStdReset.sh:151` (function call)

---

## 3. Documentation Changes

### 3.1 README.md
**Required Changes:**
1. Update line 11: Change "lock a `.lockfile`" to "lock a `.lockfile` (with `.changefile` tracking changes)"
2. Update line 13-17: Explain the dual-file approach
3. Add note about `.changefile` containing metadata, `.lockfile` being locked

**Code Location:** `README.md:11-17`

---

### 3.2 Comments in Scripts
**Required Changes:**
Update comments in:
1. `lock.sh:5` - Update description
2. `unlock.sh:5` - Update description
3. All hook files - Update comments mentioning `.lockfile`

---

## 4. Helper Function Needed

### 4.1 New Utility Function: `get_lockfile_from_changefile()`
**Purpose:** Convert `.changefile` path to `.lockfile` path

**Implementation:**
```bash
get_lockfile_from_changefile() {
    local changefile_path="$1"
    local dir_path=$(dirname "$changefile_path")
    echo "$dir_path/.lockfile"
}
```

**Location:** Add to `FreeCAD_Automation/utils.sh`

**Usage:** All hooks and scripts that need to check locks after finding `.changefile`

---

## 5. Migration Strategy

### Phase 1: Core Changes
1. Modify `create_lockfile()` in FCStdFileTool.py
2. Add `--changefile` flag support
3. Update export logic to handle both files

### Phase 2: Utility Functions
1. Rename `get_FCStd_file_from_lockfile()` → `get_FCStd_file_from_changefile()`
2. Add `get_lockfile_from_changefile()` helper
3. Update `get_FCStd_dir()` to use changefile
4. Update `FCStd_file_has_valid_lock()` logic

### Phase 3: Shell Scripts
1. Update all grep patterns in hooks
2. Update variable names throughout
3. Update function calls

### Phase 4: Configuration & Documentation
1. Update init-repo.sh to track `.changefile`
2. Update README.md
3. Update inline comments

### Phase 5: Testing
1. Test export creates both files correctly
2. Test lock/unlock still works
3. Test all hooks with changefile
4. Test stash/reset operations

---

## 6. Backward Compatibility Considerations

### 6.1 Existing Repositories
- Repositories with existing `.lockfile` files will need migration
- Consider adding migration script to convert `.lockfile` → `.changefile`
- Keep `--lockfile` flag for compatibility

### 6.2 Git LFS
- `.lockfile` remains locked via git-lfs (no change)
- `.changefile` is regular tracked file (not locked)
- Both files live in same directory

---

## 7. Summary of File Modifications

| File | Lines to Modify | Complexity | Priority |
|------|----------------|------------|----------|
| FCStdFileTool.py | 455-470, 5, 31-32, 115, 492-500, 514-517 | HIGH | 1 |
| utils.sh | 147-260 (3 functions) | HIGH | 2 |
| pre-commit | 24-39 | MEDIUM | 3 |
| pre-push | 59-74 | MEDIUM | 3 |
| post-checkout | 54-87 | MEDIUM | 3 |
| post-commit | 35-47 | MEDIUM | 3 |
| post-merge | 51-84 | MEDIUM | 3 |
| post-rewrite | 45-78 | MEDIUM | 3 |
| FCStdStash.sh | 53, 75, 96, 110 | MEDIUM | 4 |
| FCStdReset.sh | 28, 76, 91, 99, 151 | MEDIUM | 4 |
| init-repo.sh | 190-199 | LOW | 5 |
| lock.sh | None (comments only) | LOW | 6 |
| unlock.sh | None (comments only) | LOW | 6 |
| README.md | 11-17 | LOW | 6 |

**Total Files to Modify:** 14 files
**Estimated Lines of Code Changed:** ~150-200 lines

---

## 8. Key Design Decisions

1. **Why keep `.lockfile`?**
   - Git LFS locking mechanism requires a file to lock
   - Changing to lock `.changefile` would require updating all lock/unlock logic
   - Simpler to keep `.lockfile` as the locked file with dummy content

2. **Why create `.changefile`?**
   - Separates metadata (timestamp, path) from lock mechanism
   - Allows tracking changes without affecting lock status
   - Provides cleaner separation of concerns

3. **File Contents:**
   - `.changefile`: Timestamp + FCStd file path (current `.lockfile` content)
   - `.lockfile`: `/dev/null` (dummy content, just for locking)

---

## 9. Testing Checklist

- [ ] Export creates both `.lockfile` and `.changefile`
- [ ] `.changefile` contains correct timestamp and path
- [ ] `.lockfile` contains `/dev/null`
- [ ] `git lock` still works with `.lockfile`
- [ ] `git unlock` still works with `.lockfile`
- [ ] All hooks detect `.changefile` changes
- [ ] Hooks correctly derive `.lockfile` path for lock checks
- [ ] Stash operations work with `.changefile`
- [ ] Reset operations work with `.changefile`
- [ ] Import operations read from `.changefile`
- [ ] Permissions set correctly based on `.lockfile` locks
- [ ] Git LFS tracks `.lockfile` as lockable
- [ ] Git tracks `.changefile` normally

---

## 10. Potential Issues & Solutions

### Issue 1: Function Name Changes
**Problem:** `get_FCStd_file_from_lockfile()` is called in many places
**Solution:** Use find/replace carefully, or create wrapper function for transition

### Issue 2: Variable Naming Consistency
**Problem:** Many variables named `*lockfile*` need renaming
**Solution:** Systematic rename: `lockfile` → `changefile`, but keep `lockfile_path` for actual lockfile

### Issue 3: Lock Checking Logic
**Problem:** Need to derive `.lockfile` path from `.changefile` path
**Solution:** Add helper function `get_lockfile_from_changefile()`

### Issue 4: Git Attributes
**Problem:** Need to ensure `.changefile` is tracked but not lockable
**Solution:** Update init-repo.sh to configure git-lfs correctly

---

## Conclusion

This migration requires careful, systematic changes across 14 files. The core change is in `FCStdFileTool.py`'s `create_lockfile()` function, with cascading updates throughout the shell scripts to search for `.changefile` instead of `.lockfile` while still using `.lockfile` for git-lfs locking.

The key insight is that `.lockfile` remains the locked file (for git-lfs), but `.changefile` becomes the tracked file that contains the actual metadata. This provides a clean separation between the locking mechanism and change tracking.