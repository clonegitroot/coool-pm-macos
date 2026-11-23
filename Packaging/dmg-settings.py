"""Finder layout; dmgbuild writes .DS_Store directly, without UI scripting."""
from pathlib import Path

app = Path(defines['app']).resolve()
background = Path(defines['background']).resolve()
files = [str(app)]
symlinks = {'Applications': '/Applications'}
icon = str(app / 'Contents/Resources/AppIcon.icns')
background = str(background)
format = 'UDZO'
compression_level = 9
filesystem = 'HFS+'
window_rect = ((160, 140), (760, 520))
default_view = 'icon-view'
icon_size = 112
text_size = 14
icon_locations = {'Coool PM.app': (210, 250), 'Applications': (550, 250)}
# FinderInfo changes invalidate a signed app bundle.
hide_extensions = []
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
show_tab_view = False
include_icon_view_settings = True
include_list_view_settings = False
