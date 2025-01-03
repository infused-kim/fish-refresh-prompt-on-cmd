# fish-refresh-prompt-on-cmd

This plugin refreshes your prompt when you enter a new command.

![fish-refresh-prompt-on-cmd demo video](img/refresh-prompt-on-cmd.gif)

In the above video you can notice...

- The time on the right was updated before the command was executed-- reflecting the actual time the command was executed
- The git status was updated... The `[!1 +1]` (1 modified, 1 untracked file) was updated to `[●6]` (6 staged files)
- After the long-running command, the command duration was shown
- After each command, first a quick prompt without git state is rendered and later the git state pops in (due to [@acomagu's fish-async-prompt plugin](https://github.com/infused-kim/fish-async-prompt/))

**But why would you want that?**

Over the past few years prompts have evolved to show an incredible amount of information, such as time, git status, dev environment, etc.

But the prompt is rendered after the previous command has finished. That's fantastic if you are actively working on something in the terminal.

However, if you take a break, make changes in another terminal tab, in your code editor or in a graphical git GUI, and come back to your terminal,then the prompt will display outdated information.

This is particularly annoying when you need to read over the terminal history to understand when commands were executed and how long they took.

**How this plugin solves the problem**

This plugin causes the prompt to be repainted before a new command is executed.

It should work with all fish prompts, but it has been designed specifically to work with the amazing [starfish prompt](https://starship.rs) and the [fish-async-prompt plugin](https://github.com/infused-kim/fish-async-prompt/) for the highest level of customization and performance.

You can find instructions on how to set up all three tools below.

## Known Issues

### fish-async-prompt sometimes not repainting

When used with fish-async-prompt, the async prompt might not repaint after the background process finishes if the background process is faster than the foreground process.

That's because the prompt has started repainting using the loading indicator prompt, but hasn't finished repainting yet. So, fish doesn't cause another repaint. But because of that the new version of the full prompt is not displayed either.

This has only happened to me when debug logging is enabled, which is why the issue is unaddressed.

It can be worked around by adding a slight delay in fish-async-prompt...:

```diff
function __async_prompt_repaint_prompt --on-signal (__async_prompt_config_internal_signal)
+    sleep 0.02
    commandline -f repaint >/dev/null 2>/dev/null
end
```
