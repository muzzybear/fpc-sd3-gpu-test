BUILDDIR = build

DEBUGFLAGS = -gl -gh
FPCFLAGS = -Mobjfpc

SHADERS = fullscreen.vert.glsl simple_xyz_rgb.vert.glsl \
    simple_xyz_rgb_uv.vert.glsl \
	solidcolor.frag.glsl uv_out.frag.glsl \
	tex_color.frag.glsl desaturate.frag.glsl \
	light_gradient.frag.glsl asdf.frag.glsl

SHADEROBJS = $(patsubst %.glsl,$(BUILDDIR)/%.spv,$(SHADERS))

APPS = foo bar baz zot qux
APPBINS = $(addprefix $(BUILDDIR)/,$(APPS))

all: $(APPBINS) $(SHADEROBJS)
.PHONY: all

clean:
	rm -r $(BUILDDIR)

$(BUILDDIR)/foo: foo.pas Matrix3DMath.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(FPCFLAGS) $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) foo.pas

$(BUILDDIR)/bar: bar.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(FPCFLAGS) $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) bar.pas

$(BUILDDIR)/baz: baz.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(FPCFLAGS) $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) baz.pas

$(BUILDDIR)/zot: zot.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(FPCFLAGS) $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) zot.pas

$(BUILDDIR)/qux: qux.pas Matrix3DMath.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(FPCFLAGS) $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) qux.pas

$(BUILDDIR)/%.vert.spv: %.vert.glsl
	@mkdir -p $(BUILDDIR)
	@glslc -fshader-stage=vert $< -o $@

$(BUILDDIR)/%.frag.spv: %.frag.glsl
	@mkdir -p $(BUILDDIR)
	@glslc -fshader-stage=frag $< -o $@
