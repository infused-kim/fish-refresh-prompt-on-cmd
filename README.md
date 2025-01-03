# fish-refresh-prompt-on-cmd

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
