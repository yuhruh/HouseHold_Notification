module ApplicationHelper
  # Header nav item: an icon (hidden from screen readers) and its label
  def nav_label(icon, label)
    safe_join([ tag.span(icon, "aria-hidden": "true"), tag.span(label) ])
  end
end
