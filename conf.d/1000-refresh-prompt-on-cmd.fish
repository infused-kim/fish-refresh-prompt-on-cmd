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
#     - The prompt shows the output of the `fish_prompt` and
#       `fish_right_prompt` functions
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
#   - We replace the original prompt functions with our wrapper functions that
#     will be called during prompt rendering as well as re-rendering on
#     refresh.
#   - After `fish_right_prompt` runs, we set `rpoc_is_refreshing` to 0


#
# Setup
#

# Setup function that is run ONCE when the shell starts up,
# just before the first prompt is displayed
function __rpoc_setup_on_startup --on-event fish_prompt

    # Removes this function after it runs once, since it only needs to run on
    # startup
    functions -e (status current-function)

    # Don't run the setup if the shell is not interactive, but allow
    # the rest of the functions to load so that `rpoc_fish_right_prompt_time`
    # is available even in non-interactive shells
    status is-interactive
    or exit 0

    # Don't run the setup if the module is disabled
    if __rpoc_is_config_enabled__disabled
        return
    end

    __rpoc_log (status current-function) "Starting setup"

    # Create variable to track if we are in pre-exec mode
    set -g rpoc_is_refreshing 0

    # Create variables to store prompt backups that are used
    # when rpoc_disable_refresh_left or rpoc_disable_refresh_right is enabled
    set -g __rpoc_prompt_backup_fish_prompt ''
    set -g __rpoc_prompt_backup_right_prompt ''

    # Bind enter key to custom event function
    bind --preset \n __rpoc_custom_event_enter_pressed
    bind --preset \r __rpoc_custom_event_enter_pressed

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

    __rpoc_setup_compatibility_check

    __rpoc_log "Setup complete"
end


function __rpoc_setup_compatibility_check
    if functions -q __async_prompt_fire
        __rpoc_log "Setting up for async prompt"

        if not functions -q __async_prompt_orig_fish_prompt
            echo "ERROR in fish-refresh-prompt-on-cmd: Could not load init due to incompatabilities with fish-async-prompt"
            echo ""
            echo "Please make sure..."
            echo "  - That you are using a version of fish-async-prompt that backs up the original prompt functions. You can use my fork until this feature is integrated into acomagu's version: https://github.com/infused-kim/fish-async-prompt"
            echo "  - You are loading fish-refresh-prompt-on-cmd AFTER fish-async-prompt"
        end
    end
end




#
# Prompt refresh on command execution
#

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


# Wrapper functions for the original prompt functions that are called during
# prompt rendering as well as re-rendering on refresh.
#
# In the setup functions these are copied to replace the original `fish_prompt`
# and `fish_right_prompt` functions.
function __rpoc_fish_prompt
    __rpoc_log "Starting fish_prompt wrapper"

    __rpoc_execute_prompt_func "fish_prompt"

    __rpoc_log "Finished"
end


function __rpoc_fish_right_prompt
    __rpoc_log "Running fish_right_prompt wrapper"

    __rpoc_execute_prompt_func "fish_right_prompt"

    __rpoc_log "Finished"

    # Run custom event after prompt is rendered
    __rpoc_custom_event_post_prompt_rendering
end

function __rpoc_execute_prompt_func --argument-names prompt_func_name

    # Name of the variable that stores the backup of the prompt
    set -l prompt_backup_var_name '__rpoc_prompt_backup_'$prompt_func_name

    # Name of the backup prompt function we replaced
    set -l rpoc_orig_prompt_func_name '__rpoc_orig_'$prompt_func_name

    # Name of the backup prompt function that fish-async-prompt replaced
    set -l async_prompt_orig_prompt_func_name '__async_prompt_orig_'$prompt_func_name

    # The output of the prompt we will display later
    set -l prompt_output

    # In refresh mode, but refresh right prompt is disabled...
    # Show the backup of the prompt
    if test "$rpoc_is_refreshing" = 1; and __rpoc_is_config_enabled__disable_refresh_right
        __rpoc_log "Refresh disabled, using backup prompt"

        set prompt_output $$prompt_backup_var_name

    # In refresh mode, and using fish-async-prompt..
    #
    # fish-async-prompt runs the prompt in a subshell and stores the output
    # in a file. Then it sends a signal to notify the main shell that the async
    # process has finished and then the prompt is refreshed.
    #
    # But the repaint command in `__rpoc_custom_event_enter_pressed` does not
    # trigger the `__async_prompt_fire` function that runs the async prompt.
    #
    # We also can't run it async because by the time it would finish, the next
    # command would have been executed and the repaint wouldn't apply to the
    # pre-command prompt, but to the post-command prompt.
    #
    # So, we run and display the original prompt function that
    # fish-async-prompt replaced (such as the real starfish function).
    #
    # Otherwise we would just get the outdated output of the previous async
    # prompt generation.
    else if test "$rpoc_is_refreshing" = 1; and functions -q $async_prompt_orig_prompt_func_name

        __rpoc_log "Running original prompt: $async_prompt_orig_prompt_func_name"
        rpoc_is_refreshing=$rpoc_is_refreshing $async_prompt_orig_prompt_func_name | read -z prompt_output

    else
        __rpoc_log "Running original prompt: $rpoc_orig_prompt_func_name"

        # Run the original prompt function if it exists, otherwise use empty
        # prompt.
        #
        # If fish-async-prompt is used, this is their prompt function that
        # displays the result of the async prompt process. Since we are not in
        # refresh mode, but in "first prompt paint mode", the
        # `fish-async-prompt` function was already run and the result is in the
        # tmpdir.
        if functions -q $rpoc_orig_prompt_func_name
            rpoc_is_refreshing=$rpoc_is_refreshing $rpoc_orig_prompt_func_name | read -z prompt_output
        else
            set prompt_output ''
        end
    end

    # Store backup of the prompt
    set -g $prompt_backup_var_name $prompt_output

    # Output the prompt
    printf '%s' $prompt_output
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
