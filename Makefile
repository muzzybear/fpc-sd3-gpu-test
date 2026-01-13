BUILDDIR = build

SHADERS = fullscreen.vert.glsl solidcolor.frag.glsl

SHADEROBJS = $(patsubst %.glsl,$(BUILDDIR)/%.spv,$(SHADERS))

all: $(BUILDDIR)/foo $(SHADEROBJS)

$(BUILDDIR)/foo: foo.pas
	@mkdir -p $(BUILDDIR)
	@fpc -l- -v0 -FE$(BUILDDIR) foo.pas

$(BUILDDIR)/%.vert.spv: %.vert.glsl
	@mkdir -p $(BUILDDIR)
	@glslc -fshader-stage=vert $< -o $@

$(BUILDDIR)/%.frag.spv: %.frag.glsl
	@mkdir -p $(BUILDDIR)
	@glslc -fshader-stage=frag $< -o $@
