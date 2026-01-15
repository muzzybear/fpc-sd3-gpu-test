BUILDDIR = build

DEBUGFLAGS = -gl -gh

SHADERS = fullscreen.vert.glsl simple_xyz_rgb.vert.glsl solidcolor.frag.glsl uv_out.frag.glsl

SHADEROBJS = $(patsubst %.glsl,$(BUILDDIR)/%.spv,$(SHADERS))

all: $(BUILDDIR)/foo $(SHADEROBJS)

$(BUILDDIR)/foo: foo.pas
	@mkdir -p $(BUILDDIR)
	@fpc $(DEBUGFLAGS) -l- -v0 -FE$(BUILDDIR) foo.pas

$(BUILDDIR)/%.vert.spv: %.vert.glsl
	@mkdir -p $(BUILDDIR)
	@glslc -fshader-stage=vert $< -o $@

$(BUILDDIR)/%.frag.spv: %.frag.glsl
	@mkdir -p $(BUILDDIR)
	@glslc -fshader-stage=frag $< -o $@
