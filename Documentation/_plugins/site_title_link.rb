# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2026 Valentin Gagarin <valentin@gagarin.work>

# Just the Docs hardcodes the site header link to `/`.
# https://github.com/just-the-docs/just-the-docs/blob/v0.10.1/_includes/components/sidebar.html#L14
# Make it point to the docs root, not the top-level site.
Jekyll::Hooks.register [:pages, :documents], :post_render do |item|
  item.output.sub!('<a href="/" class="site-title',
                   '<a href="/doc/" class="site-title')
end
