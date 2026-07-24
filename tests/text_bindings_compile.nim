import freetype, harfbuzz

var library: FtLibrary
doAssert ft_init_free_type(addr library) == 0

let buffer = hb_buffer_create()
doAssert buffer != nil
hb_buffer_add_utf8(buffer, "text", 4, 0, 4)
hb_buffer_destroy(buffer)

doAssert ft_done_free_type(library) == 0
