#!/bin/bash
# Utility functions for all scripts

distribution() {
    local dtype="unknown"
    if [ -r /etc/os-release ]; then
        source /etc/os-release
        case "$ID" in
            fedora|rhel|centos)
                dtype="redhat"
            ;;
            ubuntu|debian)
                dtype="debian"
            ;;
            arch|cachyos)
                dtype="arch"
            ;;
            *)
                if [ -n "$ID_LIKE" ]; then
                    case "$ID_LIKE" in
                        *fedora*|*rhel*|*centos*)
                            dtype="redhat"
                        ;;
                        *ubuntu*|*debian*)
                            dtype="debian"
                        ;;
                        *arch*|*cachyos*)
                            dtype="arch"
                        ;;
                    esac
                fi
            ;;
        esac
    fi
    echo "$dtype"
}
