# dmgbuild settings for LibraScan — driven by scripts/make-dmg.sh via -D defines.
import os.path

app = defines['app']
appname = os.path.basename(app)

format = 'UDZO'
compression_level = 9
files = [app]
symlinks = {'Applications': '/Applications'}
hide_extension = [appname]
icon = defines.get('volicon')          # volume icon (.icns)
background = defines['background']     # HiDPI TIFF, 540×380 pt

window_rect = ((200, 120), (540, 380))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 12
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = 'bottom'
show_icon_preview = False
include_icon_view_settings = 'auto'
include_list_view_settings = 'auto'
icon_locations = {appname: (140, 190), 'Applications': (400, 190)}
