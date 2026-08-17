_rpmz__process_if_prev_is_option() {
    local prev opts
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    case $prev in
        -c|--config)
            COMPREPLY=( $(compgen -f -- $cur) )
            return 0
            ;;
        -d|--debuglevel)
            opts="emergency alert critical error warning notice info debug"
            COMPREPLY=( $(compgen -W "$opts" -- $cur) )
            return 0
            ;;
        --downloaddir|--download-path)
            COMPREPLY=( $(compgen -d -- $cur) )
            return 0
            ;;
        --enablerepo)
            opts=$(rpmz tdnf repolist disabled 2>/dev/null | awk '{if (NR > 1) print $1}')
            COMPREPLY=( $(compgen -W "$opts" -- $cur) )
            return 0
            ;;
        --disablerepo)
            opts=$(rpmz tdnf repolist enabled 2>/dev/null | awk '{if (NR > 1) print $1}')
            COMPREPLY=( $(compgen -W "$opts" -- $cur) )
            return 0
            ;;
        -i|--installroot)
            COMPREPLY=( $(compgen -d -- $cur) )
            return 0
            ;;
        --repo|--repoid)
            opts=$(rpmz tdnf repolist all 2>/dev/null | awk '{if (NR > 1) print $1}')
            COMPREPLY=( $(compgen -W "$opts" -- $cur) )
            return 0
            ;;
        --rpmverbosity)
            opts="emergency alert critical error warning notice info debug"
            COMPREPLY=( $(compgen -W "$opts" -- $cur) )
            return 0
            ;;
        --forcearch)
            opts="x86_64 aarch64"
            COMPREPLY=( $(compgen -W "$opts" -- $cur) )
            return 0
            ;;
        --releasever)
            COMPREPLY=( $(compgen -W "4.0 5.0" -- $cur) )
            return 0
            ;;
        --sec-severity)
            opts="Critical Important Moderate Low"
            COMPREPLY=( $(compgen -W "$opts" -- $cur) )
            return 0
            ;;
        --exclude|--disableplugin|--enableplugin)
            COMPREPLY=( $(compgen -W "" -- $cur) )
            return 0
            ;;
        --repofrompath|--repofromdir)
            COMPREPLY=( $(compgen -d -- $cur) )
            return 0
            ;;
        --file)
            COMPREPLY=( $(compgen -f -- $cur) )
            return 0
            ;;
        --arch)
            opts="x86_64 aarch64 noarch"
            COMPREPLY=( $(compgen -W "$opts" -- $cur) )
            return 0
            ;;
        --metadata-path)
            COMPREPLY=( $(compgen -d -- $cur) )
            return 0
            ;;
        --whatdepends|--whatrequires|--whatprovides|--whatobsoletes|--whatconflicts|--whatrecommends|--whatsuggests|--whatsupplements|--whatenhances)
            opts=$(rpmz tdnf repoquery --qf=%{name} 2>/dev/null)
            COMPREPLY=( $(compgen -W "$opts" -- $cur) )
            return 0
            ;;
        --qf)
            COMPREPLY=( $(compgen -W "" -- $cur) )
            return 0
            ;;
        --to|--from)
            opts=$(rpmz tdnf history list | awk '{if (NR > 1) print $1}')
            COMPREPLY=( $(compgen -W "$opts" -- $cur) )
            return 0
            ;;
        --setopt)
            COMPREPLY=( $(compgen -W "" -- $cur) )
            return 0
            ;;
        --rpmdefine)
            COMPREPLY=( $(compgen -W "" -- $cur) )
            return 0
            ;;
    esac
    return 1
}

_rpmz__process_if_cmd() {
    local cmd opts
    cmd="${COMP_WORDS[$1]}"
    [[ " $__cmds " =~ " $cmd " ]] || return 1
    case $cmd in
        check-local)
            [ $1 -eq $(($COMP_CWORD - 1)) ] &&
                COMPREPLY=( $(compgen -d -- $cur) )
            return 0
            ;;
        clean)
            if [ $1 -eq $(($COMP_CWORD - 1)) ]; then
                opts="packages metadata dbcache plugins expire-cache all"
            else
                return 0
            fi
            ;;
        downgrade)
            opts=$(rpmz tdnf repoquery --downgrades --qf=%{name} 2>/dev/null)
            ;;
        autoerase|autoremove|erase|reinstall|remove)
            opts=$(rpmz tdnf repoquery --installed --qf=%{name} 2>/dev/null)
            ;;
        history)
            if [ $1 -eq $(($COMP_CWORD - 1)) ]; then
              opts="init update list rollback undo redo"
            else
              return 0
            fi
            ;;
        count)
            return 0
            ;;
        distro-sync)
            opts=$(rpmz tdnf repoquery --qf=%{name} 2>/dev/null)
            ;;
        install)
            opts=$(rpmz tdnf repoquery --qf=%{name})
            ;;
        mark)
            if [ $1 -eq $(($COMP_CWORD - 1)) ]; then
                opts="install remove"
            else
                return 0
            fi
            ;;
        repolist)
            if [ $1 -eq $(($COMP_CWORD - 1)) ]; then
                opts="all enabled disabled"
            else
                return 0
            fi
            ;;
        repoquery)
            # After repoquery, offer both repoquery-specific options and package names
            local repoquery_opts="--available --duplicates --extras --file --installed --userinstalled --upgrades --downgrades --whatconflicts --whatdepends --whatenhances --whatobsoletes --whatprovides --whatrecommends --whatrequires --whatsuggests --whatsupplements --changelogs --conflicts --depends --enhances --list --location --obsoletes --provides --qf --recommends --requires --requires-pre --suggests --supplements --source"
            local pkg_names=$(rpmz tdnf repoquery --qf=%{name} 2>/dev/null)
            opts="$repoquery_opts $pkg_names"
            ;;
        update|upgrade)
            opts=$(rpmz tdnf repoquery --upgrades --qf=%{name} 2>/dev/null)
            ;;
        check|help|makecache)
            # Commands that take no arguments
            return 0
            ;;
        check-update)
            # Optional package names
            opts="$(rpmz tdnf repoquery --qf=%{name} 2>/dev/null)"
            ;;
        info)
            # Package names or scope options
            local scope_opts="installed available updates downgrades recent all"
            local pkg_names="$(rpmz tdnf repoquery --qf=%{name} 2>/dev/null)"
            opts="$scope_opts $pkg_names"
            ;;
        list)
            # Scope options or package names
            local scope_opts="installed available updates downgrades recent all"
            local pkg_names="$(rpmz tdnf repoquery --qf=%{name} 2>/dev/null)"
            opts="$scope_opts $pkg_names"
            ;;
        provides|whatprovides)
            # Capability names (files, provides, etc.) - no easy way to list these
            # Just return 0 to allow free-form input
            return 0
            ;;
        reposync)
            # Optional repository names
            opts=$(rpmz tdnf repolist all 2>/dev/null | awk '{if (NR > 1) print $1}')
            ;;
        search)
            # Search terms - no easy way to list these, allow free-form input
            return 0
            ;;
        update-to|upgrade-to)
            # Package names (with optional version)
            opts="$(rpmz tdnf repoquery --qf=%{name} 2>/dev/null)"
            ;;
        updateinfo)
            # Mode options or package names
            local mode_opts="all info summary"
            local pkg_names="$(rpmz tdnf repoquery --qf=%{name} 2>/dev/null)"
            opts="$mode_opts $pkg_names"
            ;;
    esac
    COMPREPLY=( $(compgen -W "$opts" -- $cur) )
    return 0
}

_rpmz__complete_words() {
    COMPREPLY=( $(compgen -W "$1" -- "$cur") )
}

_rpmz__complete_legacy() {
    local first_cmd_index="$1" c="$1" opts
    local __opts __cmds
    __opts="--4 -4 --6 -6 --alldeps --allowerasing --assumeno -y --assumeyes -b --best --builddeps -C --cacheonly -c --config -d --debuglevel --debugsolver --disableexcludes --disableplugin --disablerepo --downloaddir --downloadonly --enablerepo --enableplugin --exclude --forcearch --help -h -i --installroot --json --noautoremove --nodeps --nogpgcheck --nocligpgcheck --noplugins -q --quiet --reboot-required --refresh --releasever --repo --repofromdir --repofrompath --repoid --rpmdefine --rpmverbosity --sec-severity --security --setopt --skip-broken --skipconflicts --skipdigest --skipsignature --skipobsoletes --source --testonly -v --verbose --version --available --duplicates --extras --file --installed --userinstalled --upgrades --downgrades --whatdepends --whatrequires --whatenhances --whatobsoletes --whatprovides --whatrecommends --whatsuggests --whatsupplements --whatconflicts --changelogs --conflicts --depends --enhances --list --location --obsoletes --provides --qf --recommends --requires --requires-pre --suggests --supplements --all --info --summary --recent --updates --downgrades --to --from --reverse --arch --delete --download-metadata --download-path --gpgcheck --metadata-path --newest-only --norepopath --urls"
    __cmds="autoerase autoremove check check-local check-update clean count distro-sync downgrade erase help history info install list makecache mark provides whatprovides reinstall remove repolist repoquery reposync search update update-to updateinfo upgrade upgrade-to"
    _rpmz__process_if_prev_is_option && return 0
    while [ "$c" -lt "${COMP_CWORD}" ]; do
        _rpmz__process_if_cmd "$c" && return 0
        c=$((c + 1))
    done

    [[ "$cur" == -* ]] && opts="$__opts" || opts="$__cmds"
    _rpmz__complete_words "$opts"
}

_rpmz__complete_replay() {
    local prev opts
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -i|--installroot|-installroot)
            COMPREPLY=( $(compgen -d -- "$cur") )
            return 0
            ;;
        --rpmdb-path|-rpmdb-path)
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
        --forcearch|-forcearch)
            _rpmz__complete_words "x86_64 aarch64 noarch"
            return 0
            ;;
    esac

    opts="-i --installroot -installroot --rpmdb-path -rpmdb-path --forcearch -forcearch -j --json -json -h --help"
    if [[ "$cur" == -* ]]; then
        _rpmz__complete_words "$opts"
    else
        COMPREPLY=(
            $(compgen -W "$opts" -- "$cur")
            $(compgen -d -- "$cur")
        )
    fi
}

_rpmz__complete_auto() {
    local prev
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -c|--conf)
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
    esac
    _rpmz__complete_words "-c --conf -i --install -n --notify -t --timer -h --help -v --version"
}

_rpmz__complete_repo_config() {
    local c=2 prev opts
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    case "$prev" in
        -c|--config|-f|--file)
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
    esac

    opts="-c --config -f --file -j --json"
    if [[ "$cur" == -* ]]; then
        _rpmz__complete_words "$opts"
        return 0
    fi
    while [ "$c" -lt "${COMP_CWORD}" ]; do
        case "${COMP_WORDS[c]}" in
            create|edit|get|remove|removerepo|dump)
                return 0
                ;;
        esac
        c=$((c + 1))
    done
    _rpmz__complete_words "$opts create edit get remove removerepo dump"
}

_rpmz() {
    local cur compatibility_command top_level_opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    compatibility_command="tdnf"
    top_level_opts="auto repo-config replay tdnf --help --version -h"
    if [[ "${COMP_WORDS[0]##*/}" == "$compatibility_command" ]]; then
        _rpmz__complete_legacy 1
        return 0
    fi
    if [ "$COMP_CWORD" -le 1 ]; then
        _rpmz__complete_words "$top_level_opts"
        return 0
    fi

    case "${COMP_WORDS[1]}" in
        "$compatibility_command")
            _rpmz__complete_legacy 2
            ;;
        replay)
            _rpmz__complete_replay
            ;;
        auto)
            _rpmz__complete_auto
            ;;
        repo-config)
            _rpmz__complete_repo_config
            ;;
    esac
}
complete -F _rpmz -o default -o filenames rpmz tdnf

# vim: set et ts=4 sw=4 :
