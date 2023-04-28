vim.filetype.add({
  pattern = {
    [".*/%.kube/config"] = "yaml",
  },
})
