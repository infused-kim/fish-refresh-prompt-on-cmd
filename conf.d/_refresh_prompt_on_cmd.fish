# Fish 4.1+ calls the prompt functions with --final-rendering before running
# a command when fish_transient_prompt is enabled.

#
# Setup
#

# Setup function that is run ONCE when the shell starts up,
# just before the first prompt is displayed
function __rpoc_setup_on_startup --on-event fish_prompt

    # Removes this function after it runs once, since it only needs to run on
    # startup
    functions -e (status current-function)

    status is-interactive
    or return

    if __rpoc_is_config_enabled__disabled
        return
    end

    set -l fish_version (string split . -- (string match -r '^[0-9]+\.[0-9]+' -- $version))
    if test $fish_version[1] -lt 4; or begin
        test $fish_version[1] -eq 4; and test $fish_version[2] -lt 1
    end
        echo "fish-refresh-prompt-on-cmd requires fish 4.1 or newer. For older fish versions, use v1.0.0." >&2
        return
    end

    __rpoc_log "Starting setup"
    __rpoc_setup_compatibility_check

    set -g fish_transient_prompt 1
    set -g rpoc_is_refreshing 0

    # Save the last regular rendering for sides with refreshing disabled.
    set -g __rpoc_prompt_backup_fish_prompt ''
    set -g __rpoc_prompt_backup_fish_right_prompt ''

    # Backup and replace prompt functions if they exist
    if functions -q fish_prompt
        functions -c fish_prompt '__rpoc_orig_fish_prompt'
        functions -e fish_prompt
        functions -c __rpoc_fish_prompt fish_prompt
    else
        # If fish_prompt doesn't exist, just create our function
        functions -c __rpoc_fish_prompt fish_prompt
    end

    if functions -q fish_right_prompt
        functions -c fish_right_prompt '__rpoc_orig_fish_right_prompt'
        functions -e fish_right_prompt
        functions -c __rpoc_fish_right_prompt fish_right_prompt
    else
        # If fish_right_prompt doesn't exist, use our
        # `rpoc_time` function as the right prompt, but only
        # if `rpoc_time_prompt_disabled` is not enabled
        if not __rpoc_is_config_enabled__time_prompt_disabled
            functions -c rpoc_time '__rpoc_orig_fish_right_prompt'
        end

        # Set our wrapper function as the right prompt
        functions -c __rpoc_fish_right_prompt fish_right_prompt
    end

    __rpoc_log "Setup complete"
end


function __rpoc_setup_compatibility_check
    functions -q __async_prompt_config_functions
    and test "$async_prompt_enable" != 0
    or return

    for prompt_func in (__async_prompt_config_functions)
        contains -- $prompt_func fish_prompt fish_right_prompt
        or continue
        if not functions -q __async_prompt_orig_$prompt_func
            echo "fish-refresh-prompt-on-cmd could not find the original $prompt_func in fish-async-prompt." >&2
            echo "Use the default branch of acomagu/fish-async-prompt and load it before fish-refresh-prompt-on-cmd." >&2
            return
        end
    end
end


function __rpoc_fish_prompt
    __rpoc_execute_prompt_func fish_prompt $argv
end


function __rpoc_fish_right_prompt
    __rpoc_execute_prompt_func fish_right_prompt $argv
end


function __rpoc_execute_prompt_func --argument-names prompt_func_name
    set -e argv[1]
    set -l rpoc_is_refreshing 0
    if contains -- --final-rendering $argv
        set rpoc_is_refreshing 1
    end

    set -l prompt_backup_var_name __rpoc_prompt_backup_$prompt_func_name
    set -l prompt_func __rpoc_orig_$prompt_func_name
    set -l prompt_output

    set -l refresh_enabled 1
    if test "$prompt_func_name" = fish_prompt; and __rpoc_is_config_enabled__disable_refresh_left
        set refresh_enabled 0
    end
    if test "$prompt_func_name" = fish_right_prompt; and __rpoc_is_config_enabled__disable_refresh_right
        set refresh_enabled 0
    end

    if test $rpoc_is_refreshing = 1; and test $refresh_enabled = 0
        rpoc_is_refreshing=$rpoc_is_refreshing __rpoc_log "Refresh disabled, using backup prompt"
        printf '%s' $$prompt_backup_var_name
        return
    end

    # Async-prompt's wrapper displays cached output. For the final render,
    # call the theme directly so its output is ready before the command runs.
    if test $rpoc_is_refreshing = 1; and functions -q __async_prompt_orig_$prompt_func_name
        set prompt_func __async_prompt_orig_$prompt_func_name
    end

    if functions -q $prompt_func
        rpoc_is_refreshing=$rpoc_is_refreshing __rpoc_log "Running prompt: $prompt_func"
        rpoc_is_refreshing=$rpoc_is_refreshing $prompt_func $argv | read -z prompt_output
    end

    if test $rpoc_is_refreshing = 0
        set -g $prompt_backup_var_name $prompt_output
    end

    printf '%s' $prompt_output
end


#
# Time Prompt
#

# Prints `at --:--:--` when rpoc_is_refreshing == 0
# and `at 18:56:04` when rpoc_is_refreshing == 1
#
# Can be customized with the following config variables:
# set -g rpoc_time_color green
# set -g rpoc_time_prefix 'time: '
# set -g rpoc_time_prefix_color red
# set -g rpoc_time_postfix ' wow ⏰'
# set -g rpoc_time_postfix_color magenta
#
function rpoc_time
    # Get prefix from config or use default
    set -l prefix
    if set -q rpoc_time_prefix
        set prefix $rpoc_time_prefix
    else
        set prefix "at "
    end

    # Get prefix color from config or use default (normal)
    set -l prefix_color
    if set -q rpoc_time_prefix_color
        set prefix_color $rpoc_time_prefix_color
    else
        set prefix_color normal
    end

    # Get time color from config or use default (yellow)
    set -l time_color
    if set -q rpoc_time_color
        set time_color $rpoc_time_color
    else
        set time_color yellow
    end

    # Get postfix from config or use default (empty)
    set -l postfix
    if set -q rpoc_time_postfix
        set postfix $rpoc_time_postfix
    else
        set postfix ""
    end

    # Get postfix color from config or use default (normal)
    set -l postfix_color
    if set -q rpoc_time_postfix_color
        set postfix_color $rpoc_time_postfix_color
    else
        set postfix_color normal
    end

    if test -n "$rpoc_is_refreshing" -a "$rpoc_is_refreshing" = "1" 2>/dev/null
        set_color $prefix_color
        echo -n $prefix
        set_color --bold $time_color
        echo -n (date "+%H:%M:%S")
        set_color $postfix_color
        echo -n $postfix
        set_color normal
    else
        set_color $prefix_color
        echo -n $prefix
        set_color --bold $time_color
        echo -n "--:--:--"
        set_color $postfix_color
        echo -n $postfix
        set_color normal
    end
end


#
# Command Duration
#

function __rpoc_cmd_duration_postexec --on-event fish_postexec
    rpoc_cmd_duration $CMD_DURATION
end

function rpoc_cmd_duration --argument-names seconds
    # Check if duration display is disabled
    if __rpoc_is_config_enabled__cmd_duration_disabled
        return
    end

    # Get minimum duration from config or use default (3000ms)
    set -l min_duration
    if set -q rpoc_cmd_duration_min_ms
        set min_duration $rpoc_cmd_duration_min_ms
    else
        set min_duration 3000
    end

    # Only show duration for long-running commands
    if not set -q seconds[1]; or test -z "$seconds"; or test $seconds -lt $min_duration
        return
    end

    # Get prefix from config or use default
    set -l prefix
    if set -q rpoc_cmd_duration_prefix
        set prefix $rpoc_cmd_duration_prefix
    else
        set prefix "⌛ took "
    end

    # Get prefix color from config or use default (normal)
    set -l prefix_color
    if set -q rpoc_cmd_duration_prefix_color
        set prefix_color $rpoc_cmd_duration_prefix_color
    else
        set prefix_color normal
    end

    # Get duration color from config or use default (yellow)
    set -l duration_color
    if set -q rpoc_cmd_duration_color
        set duration_color $rpoc_cmd_duration_color
    else
        set duration_color yellow
    end

    # Get postfix from config or use default (empty)
    set -l postfix
    if set -q rpoc_cmd_duration_postfix
        set postfix $rpoc_cmd_duration_postfix
    else
        set postfix ""
    end

    # Get postfix color from config or use default (normal)
    set -l postfix_color
    if set -q rpoc_cmd_duration_postfix_color
        set postfix_color $rpoc_cmd_duration_postfix_color
    else
        set postfix_color normal
    end

    set -l duration_str (__rpoc_convert_seconds_to_duration $seconds 0)

    echo ''
    set_color $prefix_color
    echo -n $prefix
    set_color --bold $duration_color
    echo -n $duration_str
    set_color $postfix_color
    echo -n $postfix
    set_color normal
end

function __rpoc_convert_seconds_to_duration --argument-names seconds decimals
    set -q decimals[1]; or set decimals 0

    set -l t (
        math -s0 "$seconds/3600000" # Hours
        math -s0 "$seconds/60000"%60 # Minutes
        math -s$decimals "$seconds/1000"%60
    )

    set -l duration_str
    if test $t[1] != 0
        set duration_str "$t[1]h $t[2]m $t[3]s"
    else if test $t[2] != 0
        set duration_str "$t[2]m $t[3]s"
    else
        set duration_str "$t[3]s"
    end

    echo $duration_str
end


#
# Logging
#

# Logs a message to the debug log file if `rpoc_debug_log_enabled` is set to
# `1`.
function __rpoc_log --argument-names message
    if __rpoc_is_config_enabled__debug_log_enabled
        # Initialize debug log file in XDG cache dir or ~/.cache if not already done
        if not set -q rpoc_debug_log_path
            set -l cache_dir
            if set -q XDG_CACHE_HOME
                set cache_dir "$XDG_CACHE_HOME/fish"
            else
                set cache_dir "$HOME/.cache/fish"
            end
            mkdir -p "$cache_dir"
            set -g rpoc_debug_log_path "$cache_dir/fish_refresh_prompt_on_cmd.log"
        end

        set -l prev_func_name (__rpoc_get_prev_func_name)
        echo (date "+%Y-%m-%d %H:%M:%S") "[$prev_func_name] $message (is_refreshing: $rpoc_is_refreshing)" >> $rpoc_debug_log_path
    end
end


# Returns the name of the function that called the function that
# calls this function.
#
# Used in the debug log to print the name of the function that is logging
# the message.
function __rpoc_get_prev_func_name
    set -l stack_lines
    for line in (status stack-trace)
        if string match -q 'in function*' "$line"
            set -a stack_lines "$line"
        end
    end

    # We want the prev function of the caller
    # Fish arrays start at index 1, current function is 1, caller is 2,
    # caller of caller is 3 (what we want)
    set -l caller_line $stack_lines[3]

    # Extract function name from "in function 'name'" pattern from caller_line

    set -l caller (string match -gr "in function '([^\']+)'" "$caller_line")
    if test -z "$caller"
        set caller 'unknown-function'
    end

    echo $caller
end


# These fish events are not actually used and simply serve to debug fish events
# when `rpoc_debug` is enabled

function __rpoc_on_event_fish_prompt --on-event fish_prompt
    __rpoc_log "Fired"
end

function __rpoc_postexec --on-event fish_postexec
    __rpoc_log "Fired"
end

function __rpoc_preexec --on-event fish_preexec
    __rpoc_log "Fired"
end


#
# Settings
#
# Settings return 0 when enabled and 1 when disabled due to shell convention
# that 0 is success and 1 is failure. This allows us to check if it's enabled
# without a comparison.

# rpoc_disable is used to disable the entire module
function __rpoc_is_config_enabled__disabled
    __rpoc_is_config_enabled rpoc_disabled
    return $status
end


# rpoc_disable_refresh_left is used to disable the refresh of the left prompt
function __rpoc_is_config_enabled__disable_refresh_left
    __rpoc_is_config_enabled rpoc_disable_refresh_left
    return $status
end


# rpoc_disable_refresh_right is used to disable the refresh of the right prompt
function __rpoc_is_config_enabled__disable_refresh_right
    __rpoc_is_config_enabled rpoc_disable_refresh_right
    return $status
end


# rpoc_debug_log_enabled is used to enable the debug logging
function __rpoc_is_config_enabled__debug_log_enabled
    __rpoc_is_config_enabled rpoc_debug_log_enabled
    return $status
end


# rpoc_time_prompt_disabled is used to disable the time prompt when no right
# prompt exists
function __rpoc_is_config_enabled__time_prompt_disabled
    __rpoc_is_config_enabled rpoc_time_prompt_disabled
    return $status
end


# rpoc_cmd_duration_disabled is used to disable the command duration display
function __rpoc_is_config_enabled__cmd_duration_disabled
    __rpoc_is_config_enabled rpoc_cmd_duration_disabled
    return $status
end


# Check if a config variable is enabled
function __rpoc_is_config_enabled --argument-names var_name
    if not set -q $var_name
        return 1
    end
    set -l value (string lower $$var_name)
    if test -z "$value" # empty string
        return 1
    end
    switch "$value"
        case 1 true
            return 0
        case 0 false
            return 1
        case '*'
            return 1
    end
end
