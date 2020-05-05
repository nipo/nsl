# Cannot use env from proc below
set nsl_lib_repo_dir [file join $env(NSL_PACKAGING_ROOT) "vivado_repository"]

proc nsl_lib_add_ip_repo {} {
    global nsl_lib_repo_dir

    set tmp [get_property ip_repo_paths [current_project]]
    lappend tmp [file normalize [file join $nsl_lib_repo_dir interface]]
    lappend tmp [file normalize [file join $nsl_lib_repo_dir module]]
    set_property ip_repo_paths $tmp [current_project]

    update_ip_catalog -rebuild -scan_changes
}

set board.enableBoardIntegratorSupport 1
set_param board.repoPaths [list [file join $env(NSL_PACKAGING_ROOT) "board"]]
nsl_lib_add_ip_repo
