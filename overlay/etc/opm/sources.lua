-- opm package sources. Each entry is {name=, url=}; the registry index is
-- fetched from <url>/index.json and file URLs resolve against <url>. Add your
-- own registries here (later entries can extend or override earlier ones).
return {
  {
    name = "aurora",
    url = "https://raw.githubusercontent.com/AlexMelanFromRingo/aurora/main/registry",
  },
}
