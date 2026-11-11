{{flutter_js}}
{{flutter_build_config}}

// Mount Flutter into #flutter-host (above the three.js canvas) instead of
// taking over <body>.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      hostElement: document.getElementById('flutter-host'),
    });
    await appRunner.runApp();
  },
});
