"""GTK widget factories used across the music-widget UI."""

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Pango", "1.0")
from gi.repository import Gtk, Pango


def ctrl_btn(label: str, cb, dim: bool = False) -> Gtk.Button:
    b = Gtk.Button(label=label)
    b.add_css_class("mw-ctrl-btn")
    if dim:
        b.set_opacity(0.35)
    b.connect("clicked", cb)
    return b


def page_tab(label: str, active: bool = False, group: Gtk.ToggleButton = None) -> Gtk.ToggleButton:
    b = Gtk.ToggleButton(label=label)
    b.add_css_class("mw-page-tab")
    if group:
        b.set_group(group)
    b.set_active(active)
    return b


def list_row(icon: str, name: str, sub: str | None = None) -> Gtk.ListBoxRow:
    row = Gtk.ListBoxRow()
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_margin_start(8)
    box.set_margin_end(8)
    box.set_margin_top(3)
    box.set_margin_bottom(3)

    ic = Gtk.Label(label=icon)
    ic.add_css_class("mw-list-icon")

    lbl = Gtk.Label(label=name)
    lbl.set_halign(Gtk.Align.START)
    lbl.set_ellipsize(Pango.EllipsizeMode.END)
    lbl.set_hexpand(True)

    box.append(ic)
    box.append(lbl)

    if sub:
        sl = Gtk.Label(label=sub)
        sl.add_css_class("mw-list-sub")
        sl.set_halign(Gtk.Align.END)
        sl.set_ellipsize(Pango.EllipsizeMode.END)
        sl.set_max_width_chars(18)
        box.append(sl)

    row.set_child(box)
    return row


def loading_row(text: str = "Loading…") -> Gtk.ListBoxRow:
    row = Gtk.ListBoxRow()
    row.set_selectable(False)
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_halign(Gtk.Align.CENTER)
    box.set_margin_top(14)
    box.set_margin_bottom(14)
    spin = Gtk.Spinner()
    spin.start()
    lbl = Gtk.Label(label=text)
    lbl.add_css_class("mw-note")
    box.append(spin)
    box.append(lbl)
    row.set_child(box)
    return row


def error_row(msg: str) -> Gtk.ListBoxRow:
    row = Gtk.ListBoxRow()
    row.set_selectable(False)
    lbl = Gtk.Label(label=f"Error: {msg[:140]}")
    lbl.add_css_class("mw-note")
    lbl.set_wrap(True)
    lbl.set_margin_top(10)
    lbl.set_margin_bottom(10)
    lbl.set_margin_start(10)
    lbl.set_margin_end(10)
    row.set_child(lbl)
    return row


def clear_listbox(listbox: Gtk.ListBox) -> None:
    while listbox.get_first_child():
        listbox.remove(listbox.get_first_child())
