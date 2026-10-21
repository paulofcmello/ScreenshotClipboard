# dmgbuild layout: the app on the left, an arrow, Applications on the right.
app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}
background = defines["background"]
window_rect = ((200, 120), (640, 400))
icon_size = 128
text_size = 13
icon_locations = {"Screenshot Clipboard.app": (170, 190), "Applications": (470, 190)}
default_view = "icon-view"
show_status_bar = show_tab_view = show_toolbar = show_pathbar = show_sidebar = False
format = "UDZO"
