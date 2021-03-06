## RcppHNSW
[![Travis-CI Build Status](https://travis-ci.org/jlmelville/rcpphnsw.svg?branch=master)](https://travis-ci.org/jlmelville/rcpphnsw)
[![AppVeyor Build Status](https://ci.appveyor.com/api/projects/status/github/jlmelville/rcpphnsw?branch=master&svg=true)](https://ci.appveyor.com/project/jlmelville/rcpphnsw)
[![Coverage Status](https://img.shields.io/codecov/c/github/jlmelville/rcpphnsw/master.svg)](https://codecov.io/github/jlmelville/rcpphnsw?branch=master)

Rcpp bindings for [HNSW](https://github.com/nmslib/hnsw).

### Status

*August 8 2018*. HNSW was recently updated so that the index size can be
increased by saving the index to disk, and then specifying a larger capacity
when reloading it. See the second example below.

### HNSW

HNSW is a header-only C++ library for finding approximate nearest neighbors
(ANN) via Hierarchical Navigable Small Worlds
[(Yashunin and Malkov, 2016)](https://arxiv.org/abs/1603.09320). 
It is part of the [nmslib](https://github.com/nmslib/nmslib]) project. 

### RcppHNSW

An R package that interfaces with HNSW, taking enormous amounts of inspiration
from [Dirk Eddelbuettel](https://github.com/eddelbuettel)'s
[RcppAnnoy](https://github.com/eddelbuettel/rcppannoy) package which did the
same for the [Annoy](https://github.com/spotify/annoy) ANN C++ library.

One difference is that I use
[roxygen2](https://cran.r-project.org/package=roxygen2) to generate the man
pages. The `NAMESPACE` is still built manually, however (I don't believe you can
`export` the classes currently).

There is multithreading support for index searching using 
[RcppParallel](https://cran.r-project.org/package=RcppParallel).

### Installing

```R
devtools::install_github("jlmelville/RcppHNSW")
```

### Example

```R
library(RcppHNSW)
data <- as.matrix(iris[, -5])

# Create a new index using the L2 (squared Euclidean) distance
# nr and nc are the number of rows and columns of the data to be added, respectively
# ef and M determines speed vs accuracy trade off
# You must specify the maximum number of items to add to the index when it
# is created. But you can increase this number: see the next example
M <- 16
ef <- 200
ann <- new(HnswL2, ncol(data), nrow(data), M, ef)

# Add items to index
for (i in 1:nr) {
  ann$addItem(data[i, ])
}

# Find 4 nearest neighbors of row 1
# indexes are in res$item, distances in res$distance
# set include_distances = TRUE to get distances as well as index
res <- ann$getNNsList(data[1, ], k = 4, include_distances = TRUE)

# function interface returns results for all rows in nr x k matrices
all_knn <- RcppHNSW::get_knn(data, k = 4, distance = "l2")
# other distance options: "euclidean", "cosine" and "ip" (inner product distance)

# other distance classes:
# Cosine: HnswCosine
# Inner Product: HnswIP
```

And here's a rough equivalent of the serialization/deserialization example from
the [hnsw README](https://github.com/nmslib/hnsw#python-bindings-example).
Although the index must have its initial size specified when its created, you
can increase its size by saving it to disk, then specifying a new larger size
when you read it back, as the following demonstrates:

```R
library("RcppHNSW")
# The number of threads to use in the getAllNNs search
RcppParallel::setThreadOptions(numThreads = RcppParallel::defaultNumThreads())
set.seed(12345)

dim <- 16
num_elements <- 100000

# Generate sample data
data <- matrix(stats::runif(num_elements * dim), nrow = num_elements)

# Split data into two batches
data1 <- data[1:(num_elements / 2), ]
data2 <- data[(num_elements / 2 + 1):num_elements, ]

# Create index
M <- 16
ef <- 10
# Set the initial index size to the size of the first batch
p <- new(HnswL2, dim, num_elements / 2, M, ef)

message("Adding first batch of ", nrow(data1), " elements")
p$addItems(data1)

# Query the elements for themselves and measure recall:
idx <- p$getAllNNs(data1, k = 1)
message("Recall for the first batch: ", formatC(mean(idx == 1:nrow(data1))))

filename <- "first_half.bin"
# Serialize index
p$save(filename)

# Reinitialize and load the index
rm(p)
message("Loading index from ", filename)
# Increase the total capacity, so that it will handle the new data
p <- new(HnswL2, dim, filename, num_elements)

message("Adding the second batch of ", nrow(data2), " elements")
p$addItems(data2)

# Query the elements for themselves and measure recall:
idx <- p$getAllNNs(data, k = 1)
# You can get distances with:
# res <- p$getAllNNsList(data, k = 1, include_distances = TRUE)
# res$dist contains the distance matrix, res$item stores the indexes

message("Recall for two batches: ", formatC(mean(idx == 1:num_elements)))
unlink(filename)
```

### API

#### **DO NOT USE NAMED PARAMETERS**

Because these are wrappers around C++ code, you **cannot** use named 
parameters in the calling R code. Arguments are parsed by position. This is
most annoying in constructors, which take multiple integer arguments, e.g.

```R
### DO THIS ###
num_elements <- 100
M <- 200
ef_construction <- 16
index <- new(HnswL2, dim, num_elements, M, ef)

### DON'T DO THIS ###
index <- new(HnswL2, dim, ef_construction = 16, M = 200, num_elements = 100)
# treated as if you wrote:
index <- new(HnswL2, dim, 16, 200, 100)
```

#### OK onto the API

* `new(HnswL2, dim, max_elements, M = 16, ef_contruction = 200)` creates a new 
index using the squared L2 distance (i.e. square of the Euclidean distance),
with `dim` dimensions and a maximum size of `max_elements` items. `ef` and `M`
determine the speed vs accuracy trade off. Other classes for different distances
are: `HnswCosine` for the cosine distance and `HnswIp` for the "Inner Product"
distance (like the cosine distance without normalizing).
* `new(HnswL2, dim, filename)` load a previously saved index (see `save` below) 
with `dim` dimensions from the specified `filename`.
* `new(HnswL2, dim, filename, max_elements)` load a previously saved index (see
`save` below) with `dim` dimensions from the specified `filename`, and a new
maximum capacity of `max_elements`. This is a way to increase the capacity of
the index without a complete rebuild.
* `addItem(v)` add vector `v` to the index.
* `addItems(m)` add the row vectors of the matrix `m` to the index.
* `save(filename)` saves an index to the specified `filename`. To load an index,
use the `new(HnswL2, dim, filename)` constructor (see above).
* `getNNs(v, k)` return a vector of the indices of the `k`-nearest neighbors of
the vector `v`. Indices are numbered from one.
* `getNNsByList(v, k, include_distances = FALSE)` return a list containing a
vector named `item` with the indices of the `k`-nearest neighbors of
the vector `v`. Indices are numbered from one. If `include_distances = TRUE`
then also return a vector `distance` containing the distances.
* `getAllNNs(m, k)` return a matrix of the indices of the `k`-nearest neighbors
of each row vector in `m`. Indices are numbered from one. This can be
configured to use `nthreads` threads by calling
`RcppParallel::setThreadOptions(numThreads = nthreads)` prior to calling this
method.
* `getAllNNsByList(m, k, include_distances = FALSE)` return a list containing a
matrix named `item` with the indices of the `k`-nearest neighbors of each row
vector in `m`. Indices are numbered from one. If `include_distances = TRUE`
then also return a matrix `distance` containing the distances. This can be
configured to use `nthreads` threads by calling
`RcppParallel::setThreadOptions(numThreads = nthreads)` prior to calling this
method.

### Differences from Python Bindings

* Multi-threading support is available only when searching the index, i.e.
through `getAllNNs` or `getAllNNsList`. It's not currently turned on for 
building the index (`addItems`) because this gave disastrously bad results 
during my testing.
* Arbitrary integer labelling is not supported. Items are labelled 
`0, 1, 2 ... N`.
* The interface roughly follows the Python one but deviates with naming and also
rolls the declaration and initialization of the index into one call. And as noted
above, you must pass arguments by position, not keyword.
* I have made a change to the C++ `hnswalg.h` code to use the 
[`showUpdate` macro from RcppAnnoy](https://github.com/eddelbuettel/rcppannoy/blob/498a2c241df0fcac140d80f9ee0a6985d0f08687/inst/include/annoylib.h#L57),
rather than `std::cerr` directly.

### Note

I had to add a non-portable flag to `PKG_CPPFLAGS` (`-march=native`). This
should be the only status warning in `R CMD check`.

### License

[GPL-3 or later](https://www.gnu.org/licenses/gpl-3.0.en.html).
