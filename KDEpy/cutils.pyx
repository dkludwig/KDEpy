# -*- coding: utf-8 -*-
"""
Fast cython functions for linear binning.

Notes
-----
(1) Instead of computing the integral and fractional part of a number as
    integral = int(data_point)
    fractional = data_point % 1
using the following code is x4 times faster:
    integral = int(data_point)
    fractional = data_point - integral
    
(2) It is extremely important to type EVERYTHING with cdef or in the function
signature. If even one variable is not properly typed, much of the speed gain
is gone.
"""

cimport cython

# boundscheck(False) -> Cython is free to assume that indexing will not cause 
# any IndexErrors to be raised.

# wraparound(False) ->  If set to False, Cython is allowed to neither check 
# for nor correctly handle negative indices

# cdivision(True) -> If set to False, Cython will adjust the remainder and 
# quotient operators C types to match those of Python ints (which differ 
# when the operands have opposite signs) and raise a ZeroDivisionError 
# when the right operand is 0
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def iterate_data_1D_weighted(double[:] transformed_data, double[:] weights, double[:] result):
    """
    1D fast binning with weights. Faster than N-dimensional cython function
    because it unrolls the loops.
    
    Parameters
    ----------
    transformed_data : the transformed (scaled w.r.t grid) data
    weights : the weights
    result : array to put the results of the computation in
    """
    cdef int obs, integral
    cdef double data_point, weight, fractional, frac_times_weight
    
    obs = transformed_data.shape[0]

    for i in range(obs):
        data_point = transformed_data[i]
        weight = weights[i]
        integral = int(data_point)
        fractional = data_point - integral
        frac_times_weight = fractional * weight  # Compute product once
        result[integral + 1] += frac_times_weight
        result[integral] += weight - frac_times_weight

    return result


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def iterate_data_1D(double[:] transformed_data, double[:] result):
    """
    1D fast binning weights. Faster than N-dimensional cython function
    because it unrolls the loops.
    
    Parameters
    ----------
    transformed_data : the transformed (scaled w.r.t grid) data
    result : array to put the results of the computation in
    """
    cdef int obs, integral
    cdef double data_point, weight, fractional
    obs = transformed_data.shape[0]
    for i in range(obs):
        data_point = transformed_data[i]
        integral = int(data_point)
        fractional = data_point - integral
        result[integral] += 1 - fractional
        result[integral + 1] += fractional

    return result


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def iterate_data_2D_weighted(double[:, :] data, double[:] weights, 
                             double[:] result, long[:] grid_num, int obs_tot):
    """
    2D fast binning with weights. Faster than N-dimensional cython function
    because it unrolls the loops.
    
    Parameters
    ----------
    data : the transformed (scaled w.r.t grid) data
    weights : the weights
    result : array to put the results of the computation in
    grid_num : number of grid points in each dimension
    obs_tot : total number of observations (grid points)
    """
    cdef int obs, index, i, x_integral, y_integral, grid_num1
    cdef double x, y, weight, x_fractional, y_fractional, value, xy, y_xy, x_xy
    
    obs = data.shape[0]
    for i in range(obs):
        
        x = data[i, 0]
        y = data[i, 1]
        weight = weights[i]
        
        x_integral = int(x)
        x_fractional = x - x_integral
        y_integral = int(y)
        y_fractional = y - y_integral

        # Computations with few flops
        xy = x_fractional * y_fractional
        y_xy = y_fractional - xy
        x_xy = x_fractional - xy
        grid_num1 = grid_num[1]
        # Bottom left
        index = y_integral + x_integral * grid_num1
        result[index % obs_tot] += (xy - x_fractional - y_fractional + 1) * weight
        
        # Bottom right
        index = y_integral + (x_integral + 1) * grid_num1
        result[index % obs_tot] += x_xy * weight
        
        # Top left
        index = (y_integral + 1) + x_integral * grid_num1
        result[index % obs_tot] += y_xy * weight
        
        # Top right
        index = (y_integral + 1) + (x_integral + 1) * grid_num1
        result[index % obs_tot] += xy * weight
        
    return result

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def iterate_data_2D(double[:, :] data, double[:] result, long[:] grid_num, 
                    int obs_tot):
    """
    2D fast binning. Faster than N-dimensional cython function because it 
    unrolls the loops. See `iterate_data_2D_weighted` for commented code.
    
    Parameters
    ----------
    data : the transformed (scaled w.r.t grid) data
    weights : the weights
    result : array to put the results of the computation in
    grid_num : number of grid points in each dimension
    obs_tot : total number of observations (grid points)
    """
    cdef int obs, index, i, x_integral, y_integral, grid_num1
    cdef double x, y, x_fractional, y_fractional, value, xy, y_xy, x_xy
    
    obs = data.shape[0]
    for i in range(obs):
        x = data[i, 0]
        y = data[i, 1]
        x_integral = int(x)
        x_fractional = x - x_integral
        y_integral = int(y)
        y_fractional = y - y_integral
        xy = x_fractional * y_fractional
        y_xy = y_fractional - xy
        x_xy = x_fractional - xy
        grid_num1 = grid_num[1] 
        index = y_integral + x_integral * grid_num1
        result[index % obs_tot] += (xy - x_fractional - y_fractional + 1)
        index = y_integral + (x_integral + 1) * grid_num1
        result[index % obs_tot] += x_xy
        index = (y_integral + 1) + x_integral * grid_num1
        result[index % obs_tot] += y_xy
        index = (y_integral + 1) + (x_integral + 1) * grid_num1
        result[index % obs_tot] += xy

    return result


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def iterate_data_ND(double[:, :] data, double[:] result, long[:] grid_num, 
                    int obs_tot, long[:, :] binary_flgs):
    """
    Iterate over N-dimensional data and bin it.
    
    The idea behind this N-dimensional generalization is to pre-compute binary 
    numbers up to 2**dims. E.g. (0,0,0), (0,0,1), (0,1,0), (0,1,1), .. for 3 
    dimensions. Each tuple represent a corner in N-space. Let t_k be the tuple 
    binary value at index k, then the index computation and the value at the
    grid point may be expressed as:
        
        index = sum_i^n (x_i prod_j=i+1^n g_j)
                where x_i := (int(x_i) + 0^t_k) 
        
        value = prod_i^n (1 - (x_i % 1))^t_k * (x_i % 1)^(t_k - 1)
    
    Parameters
    ----------
    data : the transformed (scaled w.r.t grid) data
    result : array to put the results of the computation in
    grid_num : number of grid points in each dimension
    obs_tot : total number of observations (grid points)
    binary_flgs : array of shape (dims, 2**dims), counting in binary
                 this is used to to go every corner point efficiently
    """
    cdef int obs, result_index, i, dims, corners, j, flg, corner, integer_xi
    cdef double corner_value, fraction
    cdef double[:] x_i
    
    # Get the observations and dimensions of the data
    obs, dims = data.shape[0], data.shape[1]
    
    # For every dimension, there are two directions to find corners in
    corners = 2**dims

    # Loop through every data point
    for i in range(obs):
        
        # Retrieve the data point to consider
        x_i = data[i, :]
        
        # The data point will be 'assigned' to the 2**dims corners of the grid
        # that are closed to it. To do this, we loop through every corner
        for corner in range(corners):
            
            # For this corner, we must find the index (1) of the `result` array
            # to input the computed result, as well as the actual result (2).
            
            # (1) To compute the index of this corner, and the value, we must
            # again loop through x_1, x_2, ..., d_x. If g_i is the number of
            # grid points in the i'th dimension, the index is found by
            # x_1 * (g_2 * g_3 * g_4) + x_2 * (g_3 * g_4) + x_3 * (g_4) + x_4
            # = g_4( g_3(g_2(x_1) + x_2) + x_3) + x_4
            # Since we use flags to indicate x_1 or x_1 + 1, the following
            # code does the job:
            result_index = int(x_i[0])
            result_index += 0**binary_flgs[corner, 0]
            for j in range(1, dims):
                result_index *= grid_num[j]
                integer_xi = int(x_i[j])
                result_index += (integer_xi + 0**binary_flgs[corner, j])
                
            # (2) The value is found by
            # PROD_{i=0} (1 - frac(x[i))**flg * frac(x[i]) ** (1 - flg)
            corner_value = 1.0
            for j in range(dims):
                flg = binary_flgs[corner, j]
                # Compute this part of the product, using binary flags to
                # indicate whether the factor should be x_i or (1 - x_i)
                fraction = x_i[j] % 1
                corner_value *= (1 - fraction)**flg * fraction**(1 - flg)
            
            # Finished computing index and result, add to the grid corner point
            result[result_index % obs_tot] += corner_value
    
    return result


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def iterate_data_ND_weighted(double[:, :] data, double[:] weights, double[:] result, 
                    long[:] grid_num, int obs_tot, long[:, :] binary_flgs):
    """
    See `iterate_data_ND` for documentation.
    """
    cdef int obs, result_index, i, dims, corners, j, flg, corner, integer_xi
    cdef double corner_value, fraction, weight
    cdef double[:] x_i
    
    obs, dims = data.shape[0], data.shape[1]
    corners = 2**dims
    
    for i in range(obs):
        x_i = data[i, :]
        weight = weights[i]

        for corner in range(corners):
            
            result_index = int(x_i[0])
            result_index += 0**binary_flgs[corner, 0]
            for j in range(1, dims):
                result_index *= grid_num[j]
                integer_xi = int(x_i[j])
                result_index += (integer_xi + 0**binary_flgs[corner, j])

            corner_value = 1.0
            for j in range(dims):
                flg = binary_flgs[corner, j]
                fraction = x_i[j] % 1
                corner_value *= (1 - fraction)**flg * fraction**(1 - flg)
                
            result[result_index % obs_tot] += corner_value  * weight
    
    return result