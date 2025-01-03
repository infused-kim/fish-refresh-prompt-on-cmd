#
# Explanations
#
# A few notes about how fish works:
#
#   - When a command is entered,
#     - The binding `bind --preset \n __rpoc_custom_event_enter_pressed` is
#       executed first
#     - Then the event `fish_preexec` is fired, but only if the command is not
#       empty
#     - Then the command is executed and no events fire during that execution
#     - Then the event `fish_postexec` is fired, but only if the command is not
#       empty
#     - Then the event `fish_prompt` is fired
#     - Once all `fish_prompt` _events_ finish processing, then the prompt
#       _function_ `fish_prompt` is called
#     - Once it finishes, the prompt function `fish_right_prompt` is called
#
#   - About the `fish_preexec` and `fish_postexec` events:
#     - Only fired if the command is not empty
#     - The `commandline -f repaint` command does NOT work in `fish_preexec`
#     - Instead the keybind hack must be used if you want to refresh the prompt
#       before a command is executed
#
#   - About the `--on-event fish_prompt` event:
#     - Only fired when the shell is starting up and after a command
#     - NOT fired on `commandline -f repaint`
#
# Thefore...
#   - We bind the enter key to a custom event function that triggers the
#     repaint on enter.
#   - We also set the variable `rpoc_is_refreshing` to 1 to indicate that we
#     are in refresh mode.
#   - We also replace the original prompt functions and then set
#     `rpoc_is_refreshing` to 0 once the prompt is rendered (after the
#     fish_right_prompt function finishes)


# Don't run if the shell is not interactive
status is-interactive
or exit 0


# Setup function that is run ONCE when the shell starts up,
# just before the first prompt is displayed
function __rpoc_setup_on_startup --on-event fish_prompt
    __rpoc_log (status current-function) "Starting setup"

    # Removes this function after it runs once, since it only needs to run on startup
    functions -e (status current-function)

    # Create variable to track if we are in pre-exec mode
    set -g rpoc_is_refreshing 0

    # Create variables to store prompt backups that are used
    # when rpoc_disable_refresh_left or rpoc_disable_refresh_right is enabled
    set -g __rpoc_prompt_backup_left ''
    set -g __rpoc_prompt_backup_right ''

    # Bind enter key to custom event function
    bind --preset \n __rpoc_custom_event_enter_pressed
    bind --preset \r __rpoc_custom_event_enter_pressed

    # Backup original prompt functions
    functions -c fish_prompt '__rpoc_orig_fish_prompt'
    functions -c fish_right_prompt '__rpoc_orig_fish_right_prompt'

    # Replace original prompt functions with wrapper functions
    function fish_prompt
        __rpoc_log "Starting fish_prompt wrapper"

        if test "$rpoc_is_refreshing" = 1; and __rpoc_is_config_enabled_disable_refresh_left

            __rpoc_log "Refresh disabled, using backup prompt"
            echo -n $__rpoc_prompt_backup_left
        else
            __rpoc_log "Running original fish_prompt"

            # Run the original prompt function and store its output
            set -l prompt_output (rpoc_is_refreshing=$rpoc_is_refreshing __rpoc_orig_fish_prompt)

            # Store backup of the prompt
            set -g __rpoc_prompt_backup_left $prompt_output

            # Output the prompt
            echo -n $prompt_output
        end

        __rpoc_log "Finished"
    end

    function fish_right_prompt
        __rpoc_log "Running fish_right_prompt wrapper"

        if test "$rpoc_is_refreshing" = 1; and __rpoc_is_config_enabled_disable_refresh_right
            __rpoc_log "Refresh disabled, using backup prompt"
            echo -n $__rpoc_prompt_backup_right
        else
            __rpoc_log "Running original fish_right_prompt"

            # Run the original prompt function and store its output
            set -l prompt_output (rpoc_is_refreshing=$rpoc_is_refreshing __rpoc_orig_fish_right_prompt)

            # Store backup of the prompt
            set -g __rpoc_prompt_backup_right $prompt_output

            # Output the prompt
            echo -n $prompt_output
        end

        __rpoc_log "Running __rpoc_custom_event_post_prompt_rendering"

        # Run custom event after prompt is rendered
        __rpoc_custom_event_post_prompt_rendering

        __rpoc_log "Finished"
    end

    __rpoc_log "Setup complete"
end


# Executed whenever the enter key is pressed.
#
# Sets our tracking variable `rpoc_is_refreshing` to 1 and asks fish to
# repaint the prompt before the new command is executed.
function __rpoc_custom_event_enter_pressed
    __rpoc_log "Started"

    __rpoc_log "Setting rpoc_is_refreshing to 1"

    # Set the variable to 1 to indicate that next prompt repaint is in fact
    # a refresh
    set -g rpoc_is_refreshing 1

    __rpoc_log "Executing repaint"

    # This is what actually repaints the prompt and causes the
    # `fish_prompt` and `fish_right_prompt` functions to be called again.
    #
    # But the `fish_prompt` event is NOT fired.
    commandline -f repaint

    __rpoc_log "Executing cmd execute"

    # This makes sure the command is executed, but it doesn't actually execute
    # the command at this point. It just tells the shell that we do want to
    # execute the command.
    #
    # Before it's executed, the prompt is repainted (due to the repaint cmd),
    # the preexec events are fired, etc.
    commandline -f execute

    __rpoc_log "Finished"

end


# Called by our fish_right_prompt wrapper function after the prompt is fully
# rendered and before the command is executed.
function __rpoc_custom_event_post_prompt_rendering
    __rpoc_log "Setting rpoc_is_refreshing to 0"

    # Reset the variable to 0 to indicate that the next prompt repaint is not a
    # refresh
    set -g rpoc_is_refreshing 0

    __rpoc_log "Finished"
end


#
# Logging
#

# Logs a message to the debug log file if `__rpoc_debug` is set to `1`.
function __rpoc_log --argument-names message
    if test "$__rpoc_debug" = 1
        # Initialize debug log file in XDG cache dir or ~/.cache if not already done
        if not set -q __rpoc_debug_log
            set -l cache_dir
            if set -q XDG_CACHE_HOME
                set cache_dir "$XDG_CACHE_HOME/fish"
            else
                set cache_dir "$HOME/.cache/fish"
            end
            mkdir -p "$cache_dir"
            set -g __rpoc_debug_log "$cache_dir/fish_refresh_prompt_on_cmd.log"
        end

        set -l prev_func_name (__rpoc_get_prev_func_name)
        echo (date "+%Y-%m-%d %H:%M:%S") "[$prev_func_name] $message (is_refreshing: $rpoc_is_refreshing)" >> $__rpoc_debug_log
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

# rpoc_disable_refresh_left is used to disable the refresh of the left prompt
function __rpoc_is_config_enabled_disable_refresh_left
    __rpoc_is_config_enabled rpoc_disable_refresh_left
    return $status
end

# rpoc_disable_refresh_right is used to disable the refresh of the right prompt
function __rpoc_is_config_enabled_disable_refresh_right
    __rpoc_is_config_enabled rpoc_disable_refresh_right
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
