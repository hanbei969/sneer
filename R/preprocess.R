# Preprocessing functions for the input data.

# Preprocessing
#
# Creates a callback for use in the embedding routine. The resulting
# preprocessor will apply the specified transformations to the input data,
# and, if necessary, convert the input to a distance matrix.
#
# Pass the result of this factory function to the preprocess argument of an
# embedding function, e.g. \code{embed_prob}. Note that most of the options
# are applicable only if the input data is in the form of coordinates. In that
# case, the distance matrix will also be generated as part of the
# preprocessing after any coordinate-specific processing has occurred.
# Then, any distance matrix-specific preprocessing will be applied.
#
# A variety of common preprocessing options are available. The range scaling
# and auto scaling options are mutually exclusive, but can be combined with
# whitening if required.
#
# @param range_scale_matrix If \code{TRUE}, input coordinates will be scaled
# so that elements are between (\code{rmin}, \code{rmax}).
# @param range_scale If \code{TRUE}, input coordinates will be scaled
# @param rmin Minimum value if using \code{range_scale_matrix} and
#   \code{range_scale}.
# @param rmax Maximum value if using \code{range_scale_matrix} and
#   \code{range_scale}.
# @param auto_scale If \code{TRUE}, input coordinates will be centered and
#   scaled so that each column has a mean of 0 and a standard deviation of 1.
# @param whiten If \code{TRUE}, input coordinates will be whitened.
# @param zwhiten If \code{TRUE}, input coordinates will be whitened using the
#   ZCA transform.
# @param whiten_dims Number of components to use in the whitening preprocess.
#   Only use if \code{whiten} or \code{zwhiten} is \code{TRUE}.
# @param scale_distances If \code{TRUE}, the distance matrix will be scaled
# such that the mean distance is 1.
# @param verbose If \code{TRUE}, log information about preprocessing.
# @return A preprocessor for use by the embedding routine.
# @seealso \code{embed_prob} for how to use this function for
#   configuring an embedding.
# @examples
# # Scale the input data so the smallest element is 0, and the largest is 1.
# make_preprocess(range_scale_matrix = TRUE)
#
# # Scale the input data so the smallest element in each column is -1, and
# # the largest is 1.
# make_preprocess(range_scale = TRUE, rmin = -1)
#
# # Autoscale each column in the input data, to mean 0 and the sd 1.
# make_preprocess(auto_scale = TRUE)
#
# # Whiten the data after range scaling the matrix.
# make_preprocess(range_scale_matrix = TRUE, whiten = TRUE)
#
# # Whiten the data using 10 components.
# make_preprocess(range_scale_matrix = TRUE, whiten = TRUE, whiten_dims = 10)
#
# # Whiten the data with the ZCA technique, using 10 components.
# make_preprocess(range_scale_matrix = TRUE, zwhiten = TRUE, whiten_dims = 10)
#
# # Should be passed to the preprocess argument of an embedding function:
# \dontrun{
#  embed_prob(preprocess = make_preprocess(range_scale = TRUE, rmin = -1), ...)
# }
make_preprocess <- function(range_scale_matrix = FALSE, range_scale = FALSE,
                            rmin = 0, rmax = 1, auto_scale = FALSE,
                            tsne = FALSE,
                            whiten = FALSE, zwhiten = FALSE, whiten_dims = 30,
                            scale_distances = FALSE, scale_list = NULL,
                            verbose = TRUE) {

  if (is.null(scale_list)) {
    if (auto_scale) {
      scale_list <- list(col = "sd")
    }
    else if (range_scale_matrix) {
      scale_list <- list(mat = "range")
    }
    else if (range_scale) {
      scale_list <- list(col = "range")
    }
    else if (tsne) {
      scale_list <- list(col = "center", mat = "max")
    }
    else if (whiten) {
      scale_list <- list(col = "whiten")
    }
    else if (zwhiten) {
      scale_list <- list(col = "zca")
    }
  }

  preprocess <- list()

  preprocess$filter_zero_var_cols <- function(xm) {
    old_ncols <- ncol(xm)
    xm <- varfilter(xm)
    new_ncols <- ncol(xm)
    if (verbose) {
      message("Filtered ", old_ncols - new_ncols, " columns, ",
              new_ncols, " remaining")
    }
    xm
  }

  for (name in names(scale_list)) {
    if (name == "col") {
      scale_type <- scale_list[[name]]

      if (scale_type == "sd" || scale_type == "auto") {
        preprocess$col_sd <- function(xm) {
          sd_scale_columns(xm, verbose = verbose)
        }
      }
      else if (scale_type == "center") {
        preprocess$col_center <- function(xm) {
          center_columns(xm, verbose = verbose)
        }
      }
      else if (scale_type == "max") {
        preprocess$col_max <- function(xm) {
          max_scale_columns(xm, verbose = verbose)
        }
      }
      else if (scale_type == "range") {
        preprocess$col_range <- function(xm) {
          range_scale_columns(xm, verbose = verbose)
        }
      }
      else if (scale_type == "whiten") {
        preprocess$whiten <- function(xm) {
          whiten_dims <- min(dim(xm))
          if (verbose) {
            message("PCA whitening with ", whiten_dims, " components")
          }
          whiten(xm, ncomp = whiten_dims)
        }
      }
      else if (scale_type == "zca") {
        preprocess$zwhiten <- function(xm) {
          whiten_dims <- min(dim(xm))
          if (verbose) {
            message("ZCA Whitening with ", whiten_dims, " components")
          }
          whiten(xm, ncomp = whiten_dims, zca = TRUE)
        }
      }
      else {
        stop("Unknown column scaling '", scale_type, "'")
      }
    }
    else {
      # matrix scaling
      scale_type <- scale_list[[name]]

      if (scale_type == "sd") {
        preprocess$mat_sd <- function(xm) {
          sd_scale_matrix(xm, verbose = verbose)
        }
      }
      else if (scale_type == "center") {
        preprocess$mat_center <- function(xm) {
          center_matrix(xm, verbose = verbose)
        }
      }
      else if (scale_type == "max") {
        preprocess$mat_max <- function(xm) {
          max_scale_matrix(xm, verbose = verbose)
        }
      }
      else if (scale_type == "range") {
        preprocess$mat_range <- function(xm) {
          range_scale_matrix(xm, verbose = verbose)
        }
      }
      else {
        stop("Unknown matrix scaling '", scale_type, "'")
      }
    }
  }

  preprocess_dm <- list()
  if (scale_distances) {
    preprocess_dm$scale_distances <- function(dm) {
      dm <- scale_distances(dm)
    }
  }

  function(xm) {
    if (!methods::is(xm, "dist")) {
      xm <- as.matrix(xm)
      for (name in names(preprocess)) {
        xm <- preprocess[[name]](xm)
      }
    }

    if (methods::is(xm, "dist")) {
      dm <- as.matrix(xm)
    } else {
      dm <- distance_matrix(xm)
    }
    for (name in names(preprocess_dm)) {
      dm <- preprocess_dm[[name]](dm)
    }

    utils::flush.console()
    result <- list(dm = dm, dirty = TRUE)
    if (!methods::is(xm, "dist")) {
      result$xm <- xm
    }
    result
  }
}

# Column Scaling ----------------------------------------------------------

sd_scale_columns <- function(xm, verbose = FALSE) {
  if (verbose) {
    message("Centering and scaling columns to sd = 1")
  }
  scale(xm)
}

center_columns <- function(xm, verbose = FALSE) {
  if (verbose) {
    message("Centering columns to mean = 0")
  }
  # sweep(xm, 2, colSums(xm))
  scale(xm, scale = FALSE)
}

max_scale_columns <- function(xm, verbose = FALSE) {
  if (verbose) {
    message("Scaling columns by abs max")
  }
  col_max_abs <- apply(xm, 2, function(x) { max(abs(x)) })
  sweep(xm, 2, col_max_abs, "/")
}

range_scale_columns <- function(xm, rmin = 0, rmax = 1, verbose = FALSE) {
  if (verbose) {
    message("Range scaling columns to (0, 1)")
  }

  xmin <- apply(xm, 2, min)

  xmax <- apply(xm, 2, max)
  xrange <- xmax - xmin
  rrange <- rmax - rmin

  xm <- sweep(xm, 2, xmin)
  xm <- sweep(xm, 2, rrange / xrange, "*")
  sweep(xm, 2, rmin, "+")
}

# Matrix Scaling ----------------------------------------------------------

sd_scale_matrix <- function(xm, verbose = FALSE) {
  if (verbose) {
    message("Centering and scaling matrix to sd = 1")
  }
  (xm - mean(xm)) / stats::sd(xm)
}


center_matrix <- function(xm, verbose = FALSE) {
  if (verbose) {
    message("Centering matrix to mean = 0")
  }
  xm - mean(xm)
}

max_scale_matrix <- function(xm, verbose = FALSE) {
  if (verbose) {
    message("Scaling matrix by abs max")
  }
  xm / abs(max(xm))
}


# Range Scale Matrix
#
# Elements are scaled so that they are within (\code{rmin}, \code{rmax}).
#
# @param xm Matrix to range scale.
# @param rmin Minimum value in the scaled matrix.
# @param rmax Maximum value in the scaled matrix.
# @return Range scaled data.
range_scale_matrix <- function(xm, rmin = 0, rmax = 1, verbose = FALSE) {
  if (verbose) {
    message("Range scaling matrix to (0, 1)")
  }
  xmin <- min(xm)
  xmax <- max(xm)
  xrange <- xmax - xmin
  rrange <- rmax - rmin

  ((xm - xmin) * (rrange / xrange)) + rmin
}

# Whitening ---------------------------------------------------------------

# Data Whitening
#
# Whitens the data so that the covariance matrix is the identity matrix
# (variances of the data are all one and the covariances are zero).
#
# Whitening consists of performing PCA on the centered (and optionally
# scaled to unit standard deviation column) input data, optionally removing
# eigenvectors corresponding to the smallest eigenvectors, and then rotating
# the data to decorrelate it. Each component is additionally scaled by the
# square root of the corresponding eigenvalue so that the variances of the
# rotated solution are all equal to one.
#
# Because whitening transformations are not unique, a further transformation
# may be carried out on the PCA whitened solution to produce the Zero-Phase
# Component Analysis (ZCA) whitening, which uses the rotation that best
# reproduces the input data in a least-squares sense, while maintaining the
# whitened properties. This may be useful for some image datasets where a
# whitening which preserves the original data structure as much as possible
# may be desirable.
#
# If ZCA is used as the whitening transform then the returned whitened data
# will have the same dimensionality as the input data xm, even if a value for
# \code{ncomp} was also provided. This is simply due to the form of the
# matrix multiplication that produces the ZCA transform. Additionally, ZCA
# is most often applied to images where the whitened data is intended to be
# visualized in the same way as the input data and so the dimensionality would
# need to be identical anyway. Nonetheless, the dimensionality reduction has
# still occurred, with the ZCA simply reconstructing the truncated data back
# into the original (albeit whitened) space.
#
# @param xm Matrix to whiten.
# @param scale If \code{TRUE}, then the centered columns of xm are divided by
# their standard deviations.
# @param zca If \code{TRUE}, then apply the Zero-Phase Component Analysis
# (ZCA) whitening. If ZCA is used then the returned whitened data will have
# as many columns as was in the input data, even if a value of \code{ncomp}
# was specified.
# @param ncomp Number of components to keep in a reduced dimension
# representation of the data.
# @param epsilon Regularization parameter to apply to eigenvalues, to avoid
# numerical instabilities with eigenvalues close to zero. Values of 1.e-5 to
# 0.1 seem common.
# @param verbose If \code{TRUE}, then debug messages will be logged.
# @return Whitened matrix.
whiten <- function(xm, scale = FALSE, zca = FALSE, ncomp = min(dim(xm)),
                   epsilon = 1.e-5, verbose = TRUE) {
  xm <- scale(xm, scale = scale)
  n <- nrow(xm)
  # This implementation does SVD directly on xm
  # Uses La.svd so that the loadings V are already transposed and we
  # only need to untranspose if ZCA is asked for.
  svdx <- La.svd(xm, nu = 0, nv = ncomp)
  dm <- diag(sqrt(n - 1) / (svdx$d[1:ncomp] + epsilon), nrow = ncomp)
  vm <- svdx$vt[1:ncomp, , drop = FALSE]
  wm <- dm %*% vm
  if (zca) {
    wm <- t(vm) %*% wm
  }
  xm %*% t(wm)
}



# Miscellaneous -----------------------------------------------------------

# Low Variance Column Filtering
#
# Removes columns from the data with variance lower than a threshold. Some
# techniques can't handle zero variance columns.
#
# @param xm Matrix to filter.
# @param minvar Minimum variance allowed for a column.
# @return Data with all columns with a variance lower than \code{minvar}
# removed.
varfilter <- function(xm, minvar = 0.0) {
  vars <- apply(xm, 2, stats::var)
  xm[, vars > minvar, drop = FALSE]
}

# Input Distance Scaling
#
# Preprocess function for distance matrix.
#
# Scales the input distances so that the mean distance is 1. This preprocessing
# step is recommended as part of the \code{nerv} embedding method.
#
# @param dm Distance matrix
# @param verbose If \code{TRUE}, information about the scaled distances will be
# logged.
# @return Scaled distance matrix.
#
# @references
# Venna, J., Peltonen, J., Nybo, K., Aidos, H., & Kaski, S. (2010).
# Information retrieval perspective to nonlinear dimensionality reduction for
# data visualization.
scale_distances <- function(dm, verbose = TRUE) {
  dm <- dm / mean(upper_tri(dm))
  if (verbose) {
    summarize(upper_tri(dm), "Scaled Dist")
  }
  dm
}
