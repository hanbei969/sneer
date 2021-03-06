library(sneer)
context("Gradients")

# This tests that the analytical gradients match those from a finite difference
# calculation.

inp_df <- iris[1:50, 1:4]
nr <- nrow(inp_df)
betas <- seq(1e-3, 1, length.out = nr)
preprocess <- make_preprocess(range_scale_matrix = TRUE,  verbose = FALSE)
out_init <- out_from_PCA(verbose = FALSE)
inp_init <- inp_from_perp(perplexity = 20, verbose = FALSE)
inp_aw <- function() { inp_from_perp(perplexity = 45, verbose = FALSE) }
inp_ms <- function() { inp_from_perps_multi(perplexities = seq(45, 25, length.out = 3),
                                num_scale_iters = 0, verbose = FALSE) }
inp_ums <- function() { inp_from_perps_multi(perplexities = seq(45, 25, length.out = 3),
                               num_scale_iters = 0, modify_kernel_fn = NULL,
                               verbose = FALSE) }
inp_tms <- function() { inp_from_perps_multi(perplexities = seq(45, 25, length.out = 3),
                                num_scale_iters = 0,
                                modify_kernel_fn = transfer_kernel_precisions,
                                verbose = FALSE) }

pluginize <- function(method) {
  method$stiffness <- plugin_stiffness()
  method
}

distance_pluginize <- function(method) {
  method$stiffness <- distance_stiffness()
  method
}

gfd <- function(embedder, diff = .Machine$double.eps ^ (1 / 3)) {
  gradient_fd(embedder$inp, embedder$out, embedder$method, diff = diff)$gm
}

gan <- function(embedder) {
  grad <- dist2_gradient()
  if (!is.null(embedder$method$gradient)) {
    grad <- embedder$method$gradient
  }
  grad$fn(embedder$inp, embedder$out, embedder$method)$gm
}

# useful for interactive examination of analytical gradients only, diff param is
# ignored, but means you don't have to delete so much when changing a call to
# hgfd
hgan <- function(method, inp_init = inp_from_perp(perplexity = 20,
                                                  verbose = FALSE),
                 inp_df = iris[1:50, 1:4],
                 diff = .Machine$double.eps ^ (1 / 3)) {

  embedder <- init_embed(inp_df, method,
                         preprocess = make_preprocess(verbose = FALSE),
                         init_inp = inp_init,
                         init_out = out_from_PCA(verbose = FALSE),
                         opt = mize_grad_descent())
  head(gan(embedder))
}

# useful for interactive examination of analytical gradients only
hgfd <- function(method,
                 inp_init = inp_from_perp(perplexity = 20,
                                          verbose = FALSE),
                 inp_df = iris[1:50, 1:4],
                 diff = .Machine$double.eps ^ (1 / 3)) {
  embedder <- init_embed(inp_df, method,
                         preprocess = make_preprocess(verbose = FALSE),
                         init_inp = inp_init,
                         init_out = out_from_PCA(verbose = FALSE),
                         opt = mize_grad_descent())
  head(gfd(embedder, diff = diff))
}

expect_grad <- function(method,
                        label = "",
                        info = label,
                        inp_init = inp_from_perp(perplexity = 20,
                                                 verbose = FALSE),
                        diff = .Machine$double.eps ^ (1 / 3),
                        tolerance = 1e-6,
                        scale = 1,
                        inp_df = iris[1:50, 1:4]) {

  embedder <- init_embed(inp_df, method,
                         preprocess = preprocess,
                         init_inp = inp_init,
                         init_out = out_init,
                         opt = mize_grad_descent())
  grad_fd <- gfd(embedder, diff = diff)
  grad_an <- gan(embedder)
  attr(grad_an, "dimnames") <- NULL

  expect_equal(grad_an, grad_fd, tolerance = tolerance, scale = scale,
               label = label, info = info,
               expected.label = "finite difference gradient")
}

expect_grad_equal <- function(method1, method2,
                           label = "",
                           info = label,
                           inp_init = inp_from_perp(perplexity = 20,
                                                    verbose = FALSE),
                           diff = .Machine$double.eps ^ (1 / 3),
                           tolerance = 1e-6,
                           scale = 1,
                           inp_df = iris[1:50, 1:4]) {

  embedder1 <- init_embed(inp_df, method1,
                         preprocess = preprocess,
                         init_inp = inp_init,
                         init_out = out_init,
                         opt = mize_grad_descent())
  grad_an1 <- gan(embedder1)

  embedder2 <- init_embed(inp_df, method2,
                          preprocess = preprocess,
                          init_inp = inp_init,
                          init_out = out_init,
                          opt = mize_grad_descent())
  grad_an2 <- gan(embedder2)

  expect_equal(grad_an1, grad_an2, tolerance = tolerance, scale = scale,
               label = label, info = info,
               expected.label = "analytical gradients")
}

test_that("Distance gradients", {
  expect_grad(mmds(), inp_init = NULL, label = "mmds")
  expect_grad(smmds(), inp_init = NULL, label = "smmds")
  expect_grad(sammon_map(), inp_init = NULL, label = "sammon")
})

test_that("Plugin distance gradients", {
  expect_grad(distance_pluginize(mmds()), inp_init = NULL, label = "plugin mmds")
  expect_grad(distance_pluginize(smmds()), inp_init = NULL, label = "plugin smmds")
  expect_grad(distance_pluginize(sammon_map()), inp_init = NULL,
              label = "plugin sammon")
})

test_that("SNE gradients", {
  expect_grad(asne(), label = "asne")
  expect_grad(ssne(), label = "ssne")
  expect_grad(tsne(), label = "tsne")
  expect_grad(tasne(), label = "tasne")
})

test_that("Heavy Tailed gradient", {
  expect_grad(hssne(), label = "hssne", diff = 1e-4)
})

test_that("Reverse SNE gradients", {
  expect_grad(rasne(), label = "rasne")
  expect_grad(rssne(), label = "rssne")
  expect_grad(rtsne(), label = "rtsne")
})

test_that("SNE gradients with asymmetric weights", {
  expect_grad(asne(beta = betas), label = "asne-aw", inp_init = inp_aw())
  expect_grad(rasne(beta = betas), label = "rasne-aw", inp_init = inp_aw())
})

test_that("NeRV gradients", {
  expect_grad(nerv(beta = betas), label = "nerv", inp_init = inp_aw())
  expect_grad(snerv(beta = betas), label = "snerv", inp_init = inp_aw())
  expect_grad(hsnerv(beta = betas), label = "hsnerv", inp_init = inp_aw())

  # test nerv with cond probs
  expect_grad(embedder(cost = "nerv", kernel = "exp", beta = betas,
                       norm = c("joint", "pair")),
              label = "nerv_jp", inp_init = inp_aw())
  expect_grad(embedder(cost = "nerv", kernel = "exp", beta = betas,
                       norm = "joint"),
              label = "nerv_j", inp_init = inp_aw())
  expect_grad(embedder(cost = "nerv", kernel = "exp", beta = betas,
                       norm = "pair"),
              label = "nerv_p", inp_init = inp_aw())
})

test_that("NeRV gradients with fixed (or no) precision", {
  expect_grad(nerv(beta = 1), label = "unerv b=1")
  expect_grad(snerv(beta = 1), label = "usnerv b=1")
  expect_grad(hsnerv(beta = 1), label = "uhsnerv b=1", diff = 1e-4)
  expect_grad(tnerv(), label = "tnerv")
})

test_that("JSE gradients", {
  expect_grad(jse(), label = "jse")
  expect_grad(sjse(), label = "sjse")
  expect_grad(hsjse(), label = "hsjse", diff = 1e-4)

  # test jse with cond probs
  expect_grad(embedder(cost = "JS", kernel = "exp", beta = betas,
                       norm = c("joint", "pair")),
              label = "sjse_jp", inp_init = inp_aw())
  expect_grad(embedder(cost = "JS", kernel = "exp", beta = betas,
                       norm = "joint"),
              label = "sjse_j", inp_init = inp_aw())
  expect_grad(embedder(cost = "JS", kernel = "exp", beta = betas,
                       norm = "pair"),
              label = "sjse_p", inp_init = inp_aw())
})

test_that("Plugin gradients", {
  expect_grad(pluginize(asne()), label = "plugin asne")
  expect_grad(pluginize(ssne()), label = "plugin ssne")
  expect_grad(pluginize(tsne()), label = "plugin tsne")
  expect_grad(pluginize(hssne()), label = "plugin hssne", diff = 1e-4)
  expect_grad(pluginize(tasne()), label = "plugin tasne")

  expect_grad(pluginize(rasne()), label = "plugin rasne")
  expect_grad(pluginize(rssne()), label = "plugin rssne")
  expect_grad(pluginize(rtsne()), label = "plugin rtsne")

  expect_grad(pluginize(nerv(beta = 1)), label = "plugin unerv")
  expect_grad(pluginize(snerv(beta = 1)), label = "plugin usnerv")
  expect_grad(pluginize(hsnerv(beta = 1)), label = "plugin uhsnerv",
              diff = 1e-4)
  expect_grad(pluginize(tnerv()), label = "plugin tnerv")

  expect_grad(pluginize(nerv(beta = betas)), label = "plugin nerv")

  expect_grad(pluginize(jse()), label = "plugin jse")
  expect_grad(pluginize(sjse()), label = "plugin sjse")
  expect_grad(pluginize(hsjse()), label = "plugin hsjse", diff = 1e-4)
})

test_that("Plugin gradients with asymmetric weights", {
  expect_grad(pluginize(asne(beta = betas)), label = "plugin asne-aw",
              inp_init = inp_aw())
  expect_grad(pluginize(rasne(beta = betas)), label = "plugin rasne-aw",
              inp_init = inp_aw())
  expect_grad(pluginize(ssne(beta = betas)), label = "plugin ssne-aw",
              inp_init = inp_aw())
  expect_grad(pluginize(nerv(beta = betas)), label = "plugin nerv-aw",
              inp_init = inp_aw())
  expect_grad(pluginize(snerv(beta = betas)), label = "plugin snerv-aw",
              inp_init = inp_aw())
  expect_grad(pluginize(jse(beta = betas)), label = "plugin jse-aw",
              inp_init = inp_aw())
  expect_grad(pluginize(sjse(beta = betas)), label = "plugin sjse-aw",
              inp_init = inp_aw())
})

test_that("Multiscale gradients", {
  expect_grad(pluginize(asne(verbose = FALSE)), label = "plugin ms asne",
              inp_init = inp_ms())
  expect_grad(pluginize(ssne(verbose = FALSE)), label = "plugin ms ssne",
              inp_init = inp_ms())
  expect_grad(pluginize(rasne(verbose = FALSE)), label = "plugin ms rasne",
              inp_init = inp_ms())
  expect_grad(pluginize(rssne(verbose = FALSE)), label = "plugin ms rssne",
              inp_init = inp_ms())
  expect_grad(pluginize(nerv(beta = 1, verbose = FALSE)),
              label = "plugin ms unerv", inp_init = inp_ms())
  expect_grad(pluginize(snerv(beta = 1, verbose = FALSE)),
              label = "plugin ms usnerv", inp_init = inp_ms())
  expect_grad(pluginize(nerv(beta = betas, verbose = FALSE)),
              label = "plugin ms nerv", inp_init = inp_ms())
  expect_grad(pluginize(snerv(beta = betas, verbose = FALSE)),
              label = "plugin ms snerv", inp_init = inp_ms())
  expect_grad(pluginize(jse(verbose = FALSE)), label = "plugin ms jse",
              inp_init = inp_ms())
  expect_grad(pluginize(sjse(verbose = FALSE)), label = "plugin ms sjse",
              inp_init = inp_ms())
  expect_grad(pluginize(hsjse(verbose = FALSE)),
              label = "plugin ms hsjse", inp_init = inp_ms())

  # don't rescale output precisions
  expect_grad(pluginize(asne(verbose = FALSE)),
              label = "plugin ums asne",
              inp_init = inp_ums())
  expect_grad(pluginize(ssne(verbose = FALSE)),
              label = "plugin ums ssne",
              inp_init = inp_ums())
  expect_grad(pluginize(nerv(beta = betas, verbose = FALSE)),
              label = "plugin ums nerv", inp_init = inp_ums())
  expect_grad(pluginize(snerv(beta = betas, verbose = FALSE)),
              label = "plugin ums snerv", inp_init = inp_ums())
  expect_grad(pluginize(jse(verbose = FALSE)), label = "plugin ums jse",
              inp_init = inp_ums())
  expect_grad(pluginize(sjse(verbose = FALSE)),
              label = "plugin ums sjse",
              inp_init = inp_ums())

  # The ultimate challenge: multiscale and use non-uniform kernel parameters
  expect_grad(pluginize(asne(verbose = FALSE)),
              label = "plugin tms asne", inp_init = inp_tms())
  expect_grad(pluginize(ssne(verbose = FALSE)),
              label = "plugin tms ssne",
              inp_init = inp_tms())
  expect_grad(pluginize(nerv(beta = betas, verbose = FALSE)),
              label = "plugin tms nerv", inp_init = inp_tms())
  expect_grad(pluginize(snerv(beta = betas, verbose = FALSE)),
              label = "plugin tms snerv", inp_init = inp_tms())
  expect_grad(pluginize(jse(verbose = FALSE)), label = "plugin tms jse",
              inp_init = inp_tms())
  expect_grad(pluginize(sjse(verbose = FALSE)),
              label = "plugin tms sjse", inp_init = inp_tms())
  expect_grad(pluginize(tpsne(verbose = FALSE)),
              label = "plugin tms tpsne", inp_init = inp_tms())
})

test_that("importance weighting", {
  expect_grad(imp_weight_method(ssne()), label = "wssne")
  expect_grad(imp_weight_method(pluginize(ssne())), label = "plugin wssne")
})

test_that("Dynamic HSSNE gradients", {
  expect_grad(dhssne(alpha = 0.001), label = "dhssne alpha 0.001")
  expect_grad(dhssne(alpha = 1, beta = seq(1e-3, 1, length.out = nr)),
              label = "dhssne alpha 1 beta 0.001:1")

  # Semi-symmetric version of the above
  expect_grad(dh3sne(alpha = 0.5), label = "dh3sne alpha 0.5")

  # Pair-wise version of the above
  expect_grad(dhpsne(alpha = 0.5), label = "dhpsne alpha 0.5")

  # Point-wise version
  expect_grad(dhasne(alpha = 1, beta = seq(1e-3, 1, length.out = nr)),
                label = "dhasne alpha 1 beta 0.001:1")
})

test_that("Dynamic inhomogeneous HSSNE gradients", {
  # iHSSNE fully symmetric
  expect_grad(ihssne(alpha = seq(1, 5, length.out = nr),
                     beta = seq(1e-3, 1, length.out = nr)),
              label = "ihssne alpha 1:5 beta 0.001:1")

  # iH3SNE sets input probs as joint and output probs as cond
  expect_grad(ih3sne(alpha = seq(1, 5, length.out = nr),
                     beta = seq(1e-3, 1, length.out = nr)),
              label = "ih3sne alpha 1:5 beta 0.001:1")

  # Conditional version of iHSSNE, uses prob_type = "cond" for inp and out
  expect_grad(ihpsne(alpha = seq(1, 5, length.out = nr),
                     beta = seq(1e-3, 1, length.out = nr)),
              label = "ihpsne alpha 1:5 beta 0.001:1")
})

test_that("inhomogeneous t-SNE gradients", {

  expect_grad(htsne(dof = 0.001), label = "htsne dof 0.001")
  expect_grad(htsne(dof = 1), label = "htsne dof 1")
  expect_grad(htsne(dof = 1000), label = "htsne dof 1000")

  expect_grad(itsne(dof = seq(0.001, 1, length.out = nr)),
              label = "itsne dof 0.001:1")
  expect_grad(itsne(dof = seq(1, 10, length.out = nr)),
              label = "itsne dof 1:10")
  expect_grad(itsne(dof = seq(10, 1000, length.out = nr)),
              label = "itsne dof 10:1000")
})

test_that("un-normalized embedders", {
  mmds_embedder <- embedder(cost = "square", kernel = "none",
                            transform = "none", norm = "none")
  expect_grad(mmds_embedder, inp_init = NULL, label = "embedder MMDS")
  expect_grad_equal(mmds_embedder, mmds(), inp_init = NULL,
                    label = "mmds equivalence")
  smmds_embedder <- embedder(cost = "square", kernel = "none",
                             transform = "square", norm = "none")
  expect_grad(smmds_embedder, inp_init = NULL, label = "SMMDS")
  expect_grad(smmds_embedder, smmds(), inp_init = NULL, label = "SMMDS")

  expect_grad(embedder(cost = "kl", kernel = "exp", transform = "square",
                       norm = "none"), label = "UNASNE")
  expect_grad(embedder(cost = "revKL", kernel = "exp", transform = "square",
                       norm = "none"), label = "UNrASNE")
  expect_grad(embedder(cost = "nerv", kernel = "exp", transform = "square",
                       norm = "none"), label = "UNNeRV")
  expect_grad(embedder(cost = "js", kernel = "exp", transform = "square",
                       norm = "none"), label = "UNJSE")
})

test_that("normalized distance embedders", {
  expect_grad(embedder(cost = "square", kernel = "none", transform = "none",
             norm = "point"), label = "point-norm MMDS")
  expect_grad(embedder(cost = "square", kernel = "none", transform = "none",
                       norm = "pair"), label = "pair-norm MMDS")
  expect_grad(embedder(cost = "square", kernel = "none", transform = "none",
                       norm = "pair"), label = "point-norm SMMDS")
  expect_grad(embedder(cost = "square", kernel = "none", transform = "square",
                       norm = "pair"), label = "pair-norm SMMDS")
})
