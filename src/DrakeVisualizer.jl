module DrakeVisualizer

using PyLCM
import PyCall: pyimport
import GeometryTypes: AbstractGeometry, AbstractMesh, Point, Face, vertices, faces
import AffineTransforms: AffineTransform, rotationparameters, tformeye
import Quaternions: qrotation, Quaternion
import ColorTypes: RGBA, Colorant, red, green, blue, alpha
import Base: convert

export GeometryData,
        Link,
        Robot,
        Visualizer,
        load

type GeometryData{T, GeometryType <: AbstractGeometry}
    geometry::GeometryType
    transform::AffineTransform{T, 3}
    color::RGBA{Float64}
end
GeometryData{T, GeometryType <: AbstractGeometry}(geometry::GeometryType, 
    transform::AffineTransform{T, 3},
    color::RGBA{Float64}) = GeometryData{T, GeometryType}(geometry, transform, color)
GeometryData{T, GeometryType <: AbstractGeometry}(geometry::GeometryType,
    transform::AffineTransform{T, 3}=tformeye(3),
    color=RGBA{Float64}(1., 0, 0, 0.5)) = GeometryData(geometry, transform, convert(RGBA{Float64}, color))

type Link
    geometry_data::Vector{GeometryData}
    name::ASCIIString
end
Link{T <: GeometryData}(geometry_data::Vector{T}) = Link(geometry_data, "link")

type Robot
    links::Vector{Link}
end

convert(::Type{Link}, geom::GeometryData) = Link([geom])
convert(::Type{Robot}, link::Link) = Robot([link])
convert(::Type{Robot}, links::Vector{Link}) = Robot(links)
convert(::Type{Robot}, geom::GeometryData) = convert(Robot, convert(Link, geom))

convert{T}(::Type{Vector{T}}, q::Quaternion) = T[q.s; q.v1; q.v2; q.v3]
convert{N, T1, T2}(::Type{Vector{T1}}, color::Colorant{T2, N}) = T1[red(color); green(color); blue(color); alpha(color)]
convert{T1, T2}(::Type{RGBA{T1}}, v::Vector{T2}) = RGBA{T1}(v[1], v[2], v[3], v[4])

function convert{N, T, PointType}(::Type{Array{T, 2}}, points::Vector{Point{N, PointType}})
    A = Array{T}(N, length(points))
    for i = 1:N
        for j = 1:length(points)
            A[i,j] = points[j][i]
        end
    end
    A
end

function convert{N, T, FaceType, Offset}(::Type{Array{T, 2}}, faces::Vector{Face{N, FaceType, Offset}})
    A = Array{T}(N, length(faces))
    for i = 1:N
        for j = 1:length(faces)
            A[i,j] = faces[j][i]
        end
    end
    A
end

function to_lcm{T, GeomType}(geometry_data::GeometryData{T, GeomType})
    msg = lcmdrake[:lcmt_viewer_geometry_data]()
    msg[:position] = geometry_data.transform.offset
    msg[:quaternion] = convert(Vector{Float64}, qrotation(rotationparameters(geometry_data.transform.scalefwd)))
    msg[:color] = convert(Vector{Float64}, geometry_data.color)

    if GeomType <: AbstractMesh
        msg[:type] = msg[:MESH]
        msg[:string_data] = ""
        mesh = geometry_data.geometry
        msg[:float_data] = Float64[length(vertices(mesh));
            length(faces(mesh));
            convert(Array{Float64,2}, vertices(mesh))[:];
            convert(Array{Float64,2}, map(f -> convert(Face{3, Int, -1}, f), faces(mesh)))[:];
        ]
    else
        throw("Not implemented yet")
    end
        
    msg[:num_float_data] = length(msg[:float_data])
    msg
end

function to_lcm(link::Link, robot_id_number::Real)
    msg = lcmdrake[:lcmt_viewer_link_data]()
    msg[:name] = link.name
    msg[:robot_num] = robot_id_number
    msg[:num_geom] = length(link.geometry_data)
    for geometry_data in link.geometry_data
        push!(msg["geom"], to_lcm(geometry_data))
    end
    msg
end

function to_lcm(robot::Robot, robot_id_number::Real)
    msg = lcmdrake[:lcmt_viewer_load_robot]()
    msg[:num_links] = length(robot.links)
    for link in robot.links
        push!(msg["link"], to_lcm(link, robot_id_number))
    end
    msg
end

type Visualizer
    lcm::LCM
end
Visualizer() = Visualizer(LCM())

function load(vis::Visualizer, robot::Robot, robot_id_number=1)
    msg = to_lcm(robot, robot_id_number)
    publish(vis.lcm, "DRAKE_VIEWER_LOAD_ROBOT", msg)
end 

load(vis::Visualizer, robot, robot_id_number=1) = load(vis, convert(Robot, robot), robot_id_number)

function __init__()
    const global lcmdrake = pyimport("drake")
end

end
