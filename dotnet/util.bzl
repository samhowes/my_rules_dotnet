# Avoid using non-normalized paths (workspace/../other_workspace/path)
def to_manifest_path(ctx, file):
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    else:
        return ctx.workspace_name + "/" + file.short_path
