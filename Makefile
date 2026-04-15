BUILDDIR = build

DEBUGFLAGS = -gl -gh
FPCFLAGS = -Mobjfpc -Fu3rdparty/Lazarus-SDL-3.0-Packages-and-Examples/packages/ -Fu3rdparty/LGenerics/lgenerics/

SHADERS = fullscreen.vert.glsl simple_xyz_rgb.vert.glsl \
    simple_xyz_rgb_uv.vert.glsl \
	solidcolor.frag.glsl uv_out.frag.glsl \
	tex_color.frag.glsl desaturate.frag.glsl \
	light_gradient.frag.glsl asdf.frag.glsl

SHADEROBJS = $(patsubst %.glsl,$(BUILDDIR)/%.spv,$(SHADERS))

APPS = 00 01 02 03 04 05 06 07
APPBINS = $(addprefix $(BUILDDIR)/,$(APPS))

all: $(APPBINS) $(SHADEROBJS)
.PHONY: all

clean:
	rm -r $(BUILDDIR)

$(BUILDDIR)/00: 00.pas Matrix3DMath.pas Meshbuilder.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(FPCFLAGS) $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) 00.pas

$(BUILDDIR)/01: 01.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(FPCFLAGS) $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) 01.pas

$(BUILDDIR)/02: 02.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(FPCFLAGS) $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) 02.pas

$(BUILDDIR)/03: 03.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(FPCFLAGS) $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) 03.pas

$(BUILDDIR)/04: 04.pas Matrix3DMath.pas Meshbuilder.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(FPCFLAGS) $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) 04.pas

$(BUILDDIR)/05: 05.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(FPCFLAGS) $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) 05.pas

$(BUILDDIR)/06: 06.pas Meshbuilder.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(FPCFLAGS) $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) 06.pas

$(BUILDDIR)/07: 07.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(FPCFLAGS) $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) 07.pas

$(BUILDDIR)/%.vert.spv: %.vert.glsl
	@mkdir -p $(BUILDDIR)
	@glslc -fshader-stage=vert $< -o $@

$(BUILDDIR)/%.frag.spv: %.frag.glsl
	@mkdir -p $(BUILDDIR)
	@glslc -fshader-stage=frag $< -o $@
