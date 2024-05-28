const std = @import("std");

const mach = @import("mach");
const core = mach.core;
const gpu = mach.gpu;

const imgui = @import("zig-imgui");
const imgui_mach = imgui.backends.mach;

pub const App = @This();

title_timer: core.Timer,
pipeline: *gpu.RenderPipeline,

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

pub fn init(app: *App) !void {
    try core.init(.{});

    // Pass the allocator to the backend
    imgui.setZigAllocator(&allocator);
    _ = imgui.igCreateContext(null);
    _ = imgui.ImPlot_CreateContext();

    try imgui_mach.init(allocator, core.device, .{
        .mag_filter = .nearest,
        .min_filter = .nearest,
        .mipmap_filter = .nearest,
    });

    var io: *imgui.ImGuiIO = @ptrCast(imgui.igGetIO());
    io.ConfigFlags |= imgui.ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigFlags |= imgui.ImGuiConfigFlags_DockingEnable;
    io.FontGlobalScale = 1.0 / io.DisplayFramebufferScale.y;

    const shader_module = core.device.createShaderModuleWGSL(
        "shader.wgsl",
        @embedFile("shader.wgsl"),
    );
    defer shader_module.release();

    // Fragment state
    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = core.descriptor.format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = gpu.VertexState{
            .module = shader_module,
            .entry_point = "vertex_main",
        },
    };
    const pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

    app.* = .{
        .title_timer = try core.Timer.start(),
        .pipeline = pipeline,
    };
}

pub fn deinit(app: *App) void {
    defer core.deinit();

    imgui_mach.shutdown();
    imgui.ImFontAtlas_Clear(imgui.igGetIO()[0].Fonts);
    imgui.ImPlot_DestroyContext(null);
    imgui.igDestroyContext(null);

    app.pipeline.release();

    _ = gpa.deinit();
}

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        // process events
        _ = imgui_mach.processEvent(event);
        switch (event) {
            .close => return true,
            else => {},
        }
    }

    // new frame
    try imgui_mach.newFrame();
    imgui.igNewFrame();

    try drawGui();

    const queue = core.queue;
    const back_buffer_view = core.swap_chain.getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = core.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });
    const pass = encoder.beginRenderPass(&render_pass_info);

    pass.setPipeline(app.pipeline);

    try imgui_mach.renderDrawData(@ptrCast(imgui.igGetDrawData()), pass);

    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swap_chain.present();
    back_buffer_view.release();

    // update the window title every second
    if (app.title_timer.read() >= 1.0) {
        app.title_timer.reset();
        try core.printTitle("Example App [ {d}fps ] [ Input {d}hz ]", .{
            core.frameRate(),
            core.inputRate(),
        });
    }

    return false;
}

pub fn drawGui() !void {
    imgui.igShowDemoWindow(null);
    imgui.ImPlot_ShowDemoWindow(null);
    imgui.igRender();
}
