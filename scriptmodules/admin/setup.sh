#!/usr/bin/env bash

# This file is part of The RetroEvolved Project
#
# The RetroEvolved Project is a derivative reworking of The RetroEvolved Project. The RetroEvolved Project is the legal property of its developers, whose names are
# too numerous to list here. Please refer to the COPYRIGHT.md file distributed with this source.
#
# See the LICENSE.md file at the top-level directory of this distribution and
# at https://raw.githubusercontent.com/RetroEvolved/RetroEvolved-Setup/master/LICENSE.md
#

rp_module_id="setup"
rp_module_desc="GUI based setup for RetroEvolved"
rp_module_section=""

function rps_logInit() {
    if [[ ! -d "$__logdir" ]]; then
        if mkdir -p "$__logdir"; then
            chown $user:$user "$__logdir"
        else
            fatalError "Couldn't make directory $__logdir"
        fi
    fi
    local now=$(date +'%Y-%m-%d_%H%M%S')
    logfilename="$__logdir/rps_$now.log.gz"
    touch "$logfilename"
    chown $user:$user "$logfilename"
    time_start=$(date +"%s")
}

function rps_logStart() {
    echo -e "Log started at: $(date -d @$time_start)\n"
    echo "RetroEvolved-Setup version: $__version ($(git -C "$scriptdir" log -1 --pretty=format:%h))"
    echo "System: $(uname -a)"
}

function rps_logEnd() {
    time_end=$(date +"%s")
    echo
    echo "Log ended at: $(date -d @$time_end)"
    date_total=$((time_end-time_start))
    local hours=$((date_total / 60 / 60 % 24))
    local mins=$((date_total / 60 % 60))
    local secs=$((date_total % 60))
    echo "Total running time: $hours hours, $mins mins, $secs secs"
}

function rps_printInfo() {
    reset
    if [[ ${#__ERRMSGS[@]} -gt 0 ]]; then
        printMsgs "dialog" "${__ERRMSGS[@]}"
        printMsgs "dialog" "Please see $1 for more in depth information regarding the errors."
    fi
    if [[ ${#__INFMSGS[@]} -gt 0 ]]; then
        printMsgs "dialog" "${__INFMSGS[@]}"
    fi
}

function depends_setup() {
    # check for VERSION file - if it doesn't exist we will run the post_update script as it won't be triggered
    # on first upgrade to 4.x
    if [[ ! -f "$rootdir/VERSION" ]]; then
        joy2keyStop
        exec "$scriptdir/retroevolved_packages.sh" setup post_update gui_setup
    fi

    if isPlatform "rpi" && isPlatform "mesa"; then
        printMsgs "dialog" "ERROR: You have the experimental desktop GL driver enabled. This is NOT compatible with RetroEvolved, and Emulation Station as well as emulators will fail to launch.\n\nPlease disable the experimental desktop GL driver from the raspi-config 'Advanced Options' menu."
        exit 1
    fi

    # make sure user has the correct group permissions
    if ! isPlatform "x11"; then
        local group
        for group in input video; do
            if ! hasFlag "$(groups $user)" "$group"; then
                dialog --yesno "Your user '$user' is not a member of the system group '$group'.\n\nThis is needed for RetroEvolved to function correctly. May I add '$user' to group '$group'?\n\nYou will need to restart for these changes to take effect." 22 76 2>&1 >/dev/tty && usermod -a -G "$group" "$user"
            fi
        done
    fi

    # remove all but the last 20 logs
    find "$__logdir" -type f | sort | head -n -20 | xargs -d '\n' --no-run-if-empty rm
}

function updatescript_setup()
{
    clear
    chown -R $user:$user "$scriptdir"
    printHeading "Fetching latest version of the RetroEvolved Setup Script."
    pushd "$scriptdir" >/dev/null
    if [[ ! -d ".git" ]]; then
        printMsgs "dialog" "Cannot find directory '.git'. Please clone the RetroEvolved Setup script via 'git clone https://github.com/RetroEvolved/RetroEvolved-Setup.git'"
        popd >/dev/null
        return 1
    fi
    local error
    if ! error=$(su $user -c "git pull 2>&1 >/dev/null"); then
        printMsgs "dialog" "Update failed:\n\n$error"
        popd >/dev/null
        return 1
    fi
    popd >/dev/null

    printMsgs "dialog" "Fetched the latest version of the RetroEvolved Setup script."
    return 0
}

function post_update_setup() {
    local return_func=("$@")

    echo "$__version" >"$rootdir/VERSION"

    clear
    local logfilename
    __ERRMSGS=()
    __INFMSGS=()
    rps_logInit
    {
        rps_logStart
        # run _update_hook_id functions - eg to fix up modules for retroevolved-setup 4.x install detection
        printHeading "Running post update hooks"
        rp_updateHooks
        rps_logEnd
    } &> >(tee >(gzip --stdout >"$logfilename"))
    rps_printInfo "$logfilename"

    printMsgs "dialog" "NOTICE: The RetroEvolved-Setup script and pre-made RetroEvolved SD card images are available to download for free from https://RetroGame.Club/pages/DIY-RetroEvolved \n\nThe pre-built RetroEvolved image named "RetroEvolved-Commercial" does not contain any software with non commercial licences. Therefore selling RetroEvolved-Commercial images or including RetroEvolved-Commercial with your commercial product is allowed! DO NOT include RetroEvolved-NonCommercial images in any commercial project, however, as they DO contain non-commercial licensed code! \n\nNo copyrighted games are included with ANY Offical RetroEvolved Image.\n\nIf you have been sold this software as a package including copyrighted games/ROMS, this is against the terms of use for RetroEvolved and was an illegal sale. Please contact Support@RetroGame.Club to report any violations of this policy!"

    # return to set return function
    "${return_func[@]}"
}

function package_setup() {
    local idx="$1"
    local md_id="${__mod_id[$idx]}"

    while true; do
        local options=()

        local install
        local status
        if rp_isInstalled "$idx"; then
            install="Update"
            status="Installed"
        else
            install="Install"
            status="Not installed"
        fi

        if rp_hasBinary "$idx"; then
            options+=(B "$install from binary")
        fi

        if fnExists "sources_${md_id}"; then
            options+=(S "$install from source")
        fi

        if rp_isInstalled "$idx"; then
            if fnExists "gui_${md_id}"; then
                options+=(C "Configuration / Options")
            fi
            options+=(X "Remove")
        fi

        if [[ -d "$__builddir/$md_id" ]]; then
            options+=(Z "Clean source folder")
        fi

        local help="${__mod_desc[$idx]}\n\n${__mod_help[$idx]}"
        if [[ -n "$help" ]]; then
            options+=(H "Package Help")
        fi

        cmd=(dialog --backtitle "$__backtitle" --cancel-label "Back" --menu "Choose an option for ${__mod_id[$idx]} ($status)" 22 76 16)
        choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)

        local logfilename
        __ERRMSGS=()
        __INFMSGS=()

        case "$choice" in
            B|I)
                clear
                rps_logInit
                {
                    rps_logStart
                    rp_installModule "$idx"
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            S)
                clear
                rps_logInit
                {
                    rps_logStart
                    rp_callModule "$idx" clean
                    rp_callModule "$idx"
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            C)
                rps_logInit
                {
                    rps_logStart
                    rp_callModule "$idx" gui
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            X)
                local text="Are you sure you want to remove $md_id?"
                [[ "${__mod_section[$idx]}" == "core" ]] && text+="\n\nWARNING - core packages are needed for RetroEvolved to function!"
                dialog --defaultno --yesno "$text" 22 76 2>&1 >/dev/tty || continue
                rps_logInit
                {
                    rps_logStart
                    rp_callModule "$idx" remove
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            H)
                printMsgs "dialog" "$help"
                ;;
            Z)
                rp_callModule "$idx" clean
                printMsgs "dialog" "$__builddir/$md_id has been removed."
                ;;
            *)
                break
                ;;
        esac

    done
}

function section_gui_setup() {
    local section="$1"

    local default=""
    while true; do
        local options=()

        # we don't build binaries for experimental packages
        if rp_hasBinaries && [[ "$section" != "exp" ]]; then
            options+=(B "Install/Update all ${__sections[$section]} packages from binary" "This will install all ${__sections[$section]} packages from binary archives (if available). If a binary archive is missing a source install will be performed.")
        fi

        options+=(
            S "Install/Update all ${__sections[$section]} packages from source" "S This will build and install all the packages from $section from source. Building from source will pull in the very latest releases of many of the emulators. Building could fail or resulting binaries could not work. Only choose this option if you are comfortable in working with the linux console and debugging any issues."
            X "Remove all ${__sections[$section]} packages" "X This will remove all $section packages."
        )

        local idx
        for idx in $(rp_getSectionIds $section); do
            if rp_isInstalled "$idx"; then
                installed="(Installed)"
            else
                installed=""
            fi
            options+=("$idx" "${__mod_id[$idx]} $installed" "$idx ${__mod_desc[$idx]}"$'\n\n'"${__mod_help[$idx]}")
        done

        local cmd=(dialog --backtitle "$__backtitle" --cancel-label "Back" --item-help --help-button --default-item "$default" --menu "Choose an option" 22 76 16)

        local choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
        [[ -z "$choice" ]] && break
        if [[ "${choice[@]:0:4}" == "HELP" ]]; then
            # remove HELP
            choice="${choice[@]:5}"
            # get id of menu item
            default="${choice/%\ */}"
            # remove id
            choice="${choice#* }"
            printMsgs "dialog" "$choice"
            continue
        fi

        default="$choice"

        local logfilename
        __ERRMSGS=()
        __INFMSGS=()
        case "$choice" in
            B)
                dialog --defaultno --yesno "Are you sure you want to install/update all $section packages from binary?" 22 76 2>&1 >/dev/tty || continue
                rps_logInit
                {
                    rps_logStart
                    for idx in $(rp_getSectionIds $section); do
                        rp_installModule "$idx"
                    done
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            S)
                dialog --defaultno --yesno "Are you sure you want to install/update all $section packages from source?" 22 76 2>&1 >/dev/tty || continue
                rps_logInit
                {
                    rps_logStart
                    for idx in $(rp_getSectionIds $section); do
                        rp_callModule "$idx" clean
                        rp_callModule "$idx"
                    done
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;

            X)
                local text="Are you sure you want to remove all $section packages?"
                [[ "$section" == "core" ]] && text+="\n\nWARNING - core packages are needed for RetroEvolved to function!"
                dialog --defaultno --yesno "$text" 22 76 2>&1 >/dev/tty || continue
                rps_logInit
                {
                    rps_logStart
                    for idx in $(rp_getSectionIds $section); do
                        rp_isInstalled "$idx" && rp_callModule "$idx" remove
                    done
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            *)
                package_setup "$choice"
                ;;
        esac

    done
}

function config_gui_setup() {
    local default
    while true; do
        local options=()
        local idx
        for idx in "${__mod_idx[@]}"; do
            # show all configuration modules and any installed packages with a gui function
            if [[ "${__mod_section[idx]}" == "config" ]] || rp_isInstalled "$idx" && fnExists "gui_${__mod_id[idx]}"; then
                options+=("$idx" "${__mod_id[$idx]}  - ${__mod_desc[$idx]}" "$idx ${__mod_desc[$idx]}")
            fi
        done

        local cmd=(dialog --backtitle "$__backtitle" --cancel-label "Back" --item-help --help-button --default-item "$default" --menu "Choose an option" 22 76 16)

        local choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
        [[ -z "$choice" ]] && break
        if [[ "${choice[@]:0:4}" == "HELP" ]]; then
            choice="${choice[@]:5}"
            default="${choice/%\ */}"
            choice="${choice#* }"
            printMsgs "dialog" "$choice"
            continue
        fi

        [[ -z "$choice" ]] && break

        default="$choice"

        local logfilename
        __ERRMSGS=()
        __INFMSGS=()
        rps_logInit
        {
            rps_logStart
            if fnExists "gui_${__mod_id[choice]}"; then
                rp_callModule "$choice" depends
                rp_callModule "$choice" gui
            else
                rp_callModule "$idx" clean
                rp_callModule "$choice"
            fi
            rps_logEnd
        } &> >(tee >(gzip --stdout >"$logfilename"))
        rps_printInfo "$logfilename"
    done
}

function update_packages_setup() {
    clear
    local idx
    for idx in ${__mod_idx[@]}; do
        if rp_isInstalled "$idx" && [[ -n "${__mod_section[$idx]}" ]]; then
            rp_installModule "$idx"
        fi
    done
}

function update_packages_gui_setup() {
    local update="$1"
    if [[ "$update" != "update" ]]; then
        dialog --defaultno --yesno "Are you sure you want to update installed packages?" 22 76 2>&1 >/dev/tty || return 1
        updatescript_setup
        # restart at post_update and then call "update_packages_gui_setup update" afterwards
        joy2keyStop
        exec "$scriptdir/retroevolved_packages.sh" setup post_update update_packages_gui_setup update
    fi

    local update_os=0
    dialog --yesno "Would you like to update the underlying OS packages (eg kernel etc) ?" 22 76 2>&1 >/dev/tty && update_os=1

    clear

    local logfilename
    __ERRMSGS=()
    __INFMSGS=()
    rps_logInit
    {
        rps_logStart
        [[ "$update_os" -eq 1 ]] && apt_upgrade_raspbiantools
        update_packages_setup
        rps_logEnd
    } &> >(tee >(gzip --stdout >"$logfilename"))

    rps_printInfo "$logfilename"
    printMsgs "dialog" "Installed packages have been updated."
    gui_setup
}

function basic_install_setup() {
    local idx
    for idx in $(rp_getSectionIds core) $(rp_getSectionIds main); do
        rp_installModule "$idx"
    done
}

function packages_gui_setup() {
    local section
    local default
    local options=()

    for section in core main opt driver exp; do
        options+=($section "Manage ${__sections[$section]} packages" "$section Choose top install/update/configure packages from the ${__sections[$section]}")
    done

    local cmd
    while true; do
        cmd=(dialog --backtitle "$__backtitle" --cancel-label "Back" --item-help --help-button --default-item "$default" --menu "Choose an option" 22 76 16)

        local choice
        choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
        [[ -z "$choice" ]] && break
        if [[ "${choice[@]:0:4}" == "HELP" ]]; then
            choice="${choice[@]:5}"
            default="${choice/%\ */}"
            choice="${choice#* }"
            printMsgs "dialog" "$choice"
            continue
        fi
        section_gui_setup "$choice"
        default="$choice"
    done
}

function uninstall_setup()
{
    dialog --defaultno --yesno "Are you sure you want to uninstall RetroEvolved?" 22 76 2>&1 >/dev/tty || return 0
    dialog --defaultno --yesno "Are you REALLY sure you want to uninstall RetroEvolved?\n\n$rootdir will be removed - this includes configuration files for all RetroEvolved components." 22 76 2>&1 >/dev/tty || return 0
    clear
    printHeading "Uninstalling RetroEvolved"
    for idx in "${__mod_idx[@]}"; do
        rp_isInstalled "$idx" && rp_callModule $idx remove
    done
    rm -rfv "$rootdir"
    dialog --defaultno --yesno "Do you want to remove all the files from $datadir - this includes all your installed ROMs, BIOS files and custom splashscreens." 22 76 2>&1 >/dev/tty && rm -rfv "$datadir"
    if dialog --defaultno --yesno "Do you want to remove all the system packages that RetroEvolved depends on? \n\nWARNING: this will remove packages like SDL even if they were installed before you installed RetroEvolved - it will also remove any package configurations - such as those in /etc/samba for Samba.\n\nIf unsure choose No (selected by default)." 22 76 2>&1 >/dev/tty; then
        clear
        # remove all dependencies
        for idx in "${__mod_idx[@]}"; do
            rp_isInstalled "$idx" && rp_callModule "$idx" depends remove
        done
    fi
    printMsgs "dialog" "RetroEvolved has been uninstalled."
}

function reboot_setup()
{
    clear
    reboot
}

# retroevolved-setup main menu
function gui_setup() {
    depends_setup
    local default
    while true; do
        local commit=$(git -C "$scriptdir" log -1 --pretty=format:"%cr (%h)")

        cmd=(dialog --backtitle "$__backtitle" --title "RetroEvolved-Setup Script" --cancel-label "Exit" --item-help --help-button --default-item "$default" --menu "Version: $__version\nLast Commit: $commit" 22 76 16)
        options=(
            I "Basic install" "I This will install all programs listed in Core and Main which will give you a basic RetroEvolved install. Do This First if you are beginning a fresh install! There are even more cool programs in the Optional and Experimental sections which may require advanced configuration to get running properly. If binaries are available they will be used, alternatively packages will be built from source - which will take longer."

            U "Update" "U Updates RetroEvolved-Setup and all currently installed programs. Will also allow to update OS packages. If binaries are available they will be used, otherwise programs will be built from source."

            P "Manage programs"
            "P Install/Remove and Configure RetroEvolved software, emulators, ports, and controller drivers."

            C "Configuration / tools"
            "C Configuration and Tools. Any programs you have installed that have additional configuration options will also appear here."

            S "Update RetroEvolved-Setup script"
            "S Update this RetroEvolved-Setup script. This will update this main management script only, but will not update any software packages. To update packages use the 'Update' option from the main menu, which will also update the RetroEvolved-Setup script."

            X "Uninstall RetroEvolved"
            "X Uninstall RetroEvolved completely."

            R "Perform reboot"
            "R Reboot your machine."
        )

        choice=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
        [[ -z "$choice" ]] && break

        if [[ "${choice[@]:0:4}" == "HELP" ]]; then
            choice="${choice[@]:5}"
            default="${choice/%\ */}"
            choice="${choice#* }"
            printMsgs "dialog" "$choice"
            continue
        fi
        default="$choice"

        case "$choice" in
            I)
                dialog --defaultno --yesno "Are you sure you want to do a basic install?\n\nThis will install all packages from the 'Core' and 'Main' package sections." 22 76 2>&1 >/dev/tty || continue
                clear
                local logfilename
                __ERRMSGS=()
                __INFMSGS=()
                rps_logInit
                {
                    rps_logStart
                    basic_install_setup
                    rps_logEnd
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            U)
                update_packages_gui_setup
                ;;
            P)
                packages_gui_setup
                ;;
            C)
                config_gui_setup
                ;;
            S)
                dialog --defaultno --yesno "Are you sure you want to update the RetroEvolved-Setup script ?" 22 76 2>&1 >/dev/tty || continue
                if updatescript_setup; then
                    joy2keyStop
                    exec "$scriptdir/retroevolved_packages.sh" setup post_update gui_setup
                fi
                ;;
            X)
                local logfilename
                __ERRMSGS=()
                __INFMSGS=()
                rps_logInit
                {
                    uninstall_setup
                } &> >(tee >(gzip --stdout >"$logfilename"))
                rps_printInfo "$logfilename"
                ;;
            R)
                dialog --defaultno --yesno "Are you sure you want to reboot?\n\nNote that if you reboot when Emulation Station is running, you will lose any metadata changes." 22 76 2>&1 >/dev/tty || continue
                reboot_setup
                ;;
        esac
    done
    clear
}
